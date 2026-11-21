import {createServerFn} from '@tanstack/react-start';
import {z} from 'zod';
import {requireSupabaseAuth} from '@/integrations/supabase/auth-middleware';
import type {OrderResult,ShopData,Stats} from './shop-types';
export const getShop=createServerFn({method:'GET'}).handler(async():Promise<ShopData>=>{
 const {publicClient,displayImage}=await import('./shop.server'); const client=publicClient();
 const [products,categories,slides,socials,settings]=await Promise.all([client.from('products').select('*').eq('available',true).order('position'),client.from('categories').select('*').order('position'),client.from('slides').select('*').eq('active',true).order('position'),client.from('socials').select('*').order('position'),client.from('settings').select('*').eq('id',1).single()]);
 if(products.error||categories.error||slides.error||socials.error||settings.error||!settings.data)throw new Error('Não foi possível carregar a confeitaria. Tente novamente.');
 return {products:await Promise.all((products.data??[]).map(async p=>({...p,image_url:await displayImage(p.image_url)}))),categories:categories.data??[],slides:await Promise.all((slides.data??[]).map(async s=>({...s,image_url:await displayImage(s.image_url)}))),socials:socials.data??[],settings:{...settings.data,about_image:await displayImage(settings.data.about_image),logo_url:await displayImage(settings.data.logo_url)}};
});
export const submitOrder=createServerFn({method:'POST'}).inputValidator(z.object({key:z.string().uuid(),name:z.string().trim().min(2).max(100),phone:z.string().min(10).max(20),fulfillment:z.enum(['entrega','retirada']),address:z.string().max(500),notes:z.string().max(1000),items:z.array(z.object({id:z.string().uuid(),quantity:z.number().int().min(1).max(100)})).min(1).max(30)})).handler(async({data}):Promise<OrderResult>=>{
 const {publicClient}=await import('./shop.server');const {data:result,error}=await publicClient().rpc('place_order',{_request_key:data.key,_customer_name:data.name,_phone:data.phone,_fulfillment:data.fulfillment,_address:data.address,_notes:data.notes,_items:data.items});
 if(error)throw new Error(error.message);return result as unknown as OrderResult;
});
export const recordVisit=createServerFn({method:'POST'}).inputValidator(z.object({id:z.string().uuid()})).handler(async({data})=>{const {publicClient}=await import('./shop.server');const {error}=await publicClient().rpc('record_visit',{_session_id:data.id});if(error)throw new Error('Não foi possível registrar a visita.');});
export const getStats=createServerFn({method:'POST'}).middleware([requireSupabaseAuth]).inputValidator(z.object({days:z.union([z.literal(1),z.literal(7),z.literal(30)])})).handler(async({data,context}):Promise<Stats>=>{const {data:stats,error}=await context.supabase.rpc('dashboard_stats',{_days:data.days});if(error)throw new Error('Acesso restrito à administradora.');return stats as unknown as Stats;});
