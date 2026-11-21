import type { Tables } from '@/integrations/supabase/types';
export type Product = Tables<'products'>;
export type Category = Tables<'categories'>;
export type Settings = Tables<'settings'>;
export type Slide = Tables<'slides'>;
export type Social = Tables<'socials'>;
export type Order = Tables<'orders'>;
export type ShopData = { products:Product[]; categories:Category[]; slides:Slide[]; socials:Social[]; settings:Settings };
export type CartItem = { product:Product; quantity:number };
export type OrderItem = { id:string; name:string; price:number; quantity:number };
export type OrderResult = { number:number; total:number; items:OrderItem[] };
export type Stats = { today:number; week:number; month:number; orders:number; pending:number; revenue:number; daily:{day:string;visits:number;orders:number}[]; top:{name:string;quantity:number}[] };
export const money = (amount:number) => new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(amount);
export const statuses = ['Novo','Em preparo','Pronto','Entregue','Cancelado'] as const;
export function cartTotal(items:CartItem[]) { return items.reduce((sum,item)=>sum+Math.round(item.product.price*100)*item.quantity,0)/100; }
export function whatsappUrl(phone:string,text:string) { const digits=phone.replace(/\D/g,''); return digits.length>=10 ? `https://wa.me/${digits.startsWith('55')?digits:`55${digits}`}?text=${encodeURIComponent(text)}` : null; }
export function safeLink(url:string) { try { const u=new URL(url); return u.protocol==='https:'||u.protocol==='http:' ? u.href : ''; } catch { return url.startsWith('/')&&!url.startsWith('//') ? url : ''; } }
export function orderMessage(order:OrderResult,customer:{name:string;phone:string;fulfillment:string;address:string;notes:string}) { return `Olá! Gostaria de confirmar o pedido #${order.number}.\n\n${order.items.map(i=>`${i.quantity}× ${i.name} — ${money(i.price*i.quantity)}`).join('\n')}\n\nTotal: ${money(order.total)}\nNome: ${customer.name}\nTelefone: ${customer.phone}\n${customer.fulfillment==='entrega'?`Entrega: ${customer.address}`:'Retirada na confeitaria'}${customer.notes?`\nObservações: ${customer.notes}`:''}`; }
