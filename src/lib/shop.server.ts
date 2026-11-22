import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/integrations/supabase/types';
export function publicClient() {
 const url=process.env['SUPABASE_URL']; const key=process.env['SUPABASE_PUBLISHABLE_KEY'];
 if(!url||!key) throw new Error('A confeitaria está temporariamente indisponível.');
 return createClient<Database>(url,key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(input,init)=>{const h=new Headers(init?.headers);if(key.startsWith('sb_')&&h.get('Authorization')===`Bearer ${key}`)h.delete('Authorization');h.set('apikey',key);return fetch(input,{...init,headers:h});}}});
}
// Only call after the path has been read from an RLS-approved public content row.
export async function displayImage(value:string) {
 if(!value.startsWith('storage:')) return value;
 const path=value.slice(8); if(!path||path.includes('..'))return '';
 const {supabaseAdmin}=await import('@/integrations/supabase/client.server');
 const {data,error}=await supabaseAdmin.storage.from('confeitaria').createSignedUrl(path,3600);
 if(error)throw new Error('Não foi possível carregar uma foto.');
 const browserUrl=import.meta.env['VITE_SUPABASE_URL'];
 if(!browserUrl)throw new Error('Endereço de imagens não configurado.');
 const signed=new URL(data.signedUrl); return `${browserUrl}${signed.pathname}${signed.search}`;
}
