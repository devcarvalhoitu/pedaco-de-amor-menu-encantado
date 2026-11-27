import {useState} from 'react';
import {useQuery,useQueryClient} from '@tanstack/react-query';
import {supabase} from '@/integrations/supabase/client';
import {Button} from '@/components/ui/button';
import {money} from '@/lib/shop-types';
import {toast} from 'sonner';
import {CheckCircle2,Clock3} from 'lucide-react';

type OrderRow={id:string;number:number;customer_name:string;phone:string;total:number;discount:number;payment_status:string;status:string;created_at:string;items:unknown};
export function OrdersEditor(){
 const qc=useQueryClient();const [saving,setSaving]=useState<string|null>(null);
 const q=useQuery({queryKey:['admin-orders'],refetchInterval:5000,queryFn:async()=>{const {data,error}=await supabase.from('orders').select('*').order('created_at',{ascending:false}).limit(100);if(error)throw error;return data as OrderRow[];}});
 async function setPaid(order:OrderRow){if(saving)return;setSaving(order.id);try{const {data,error}=await supabase.from('orders').update({payment_status:'Pago'}).eq('id',order.id).eq('payment_status','Pendente').select('id');if(error||!data?.length){toast.error('Não foi possível confirmar. Atualize os pedidos e tente novamente.');return;}toast.success(`Pagamento do pedido #${order.number} confirmado!`);await Promise.all([qc.invalidateQueries({queryKey:['admin-orders']}),qc.invalidateQueries({queryKey:['customer-orders']}),qc.invalidateQueries({queryKey:['admin-stats']})]);}finally{setSaving(null);}}
 if(q.isPending)return <p>Carregando pedidos...</p>;
 if(q.isError)return <section className="admin-section"><p className="text-destructive">Não foi possível carregar os pedidos.</p></section>;
 return <section className="admin-section"><h2>Pedidos e pagamentos</h2><p className="text-sm text-muted-foreground mb-4">Confirme aqui quando o valor entrar. O cliente verá Pago em Minha conta. O selo já foi incluído quando o pedido foi feito.</p><div className="editor-list">{(q.data??[]).map(o=><article key={o.id} className="editor-row"><div className="flex-1 min-w-48"><p className="font-semibold">Pedido #{o.number} · {o.customer_name}</p><p className="text-xs text-muted-foreground">{o.phone} · {new Date(o.created_at).toLocaleString('pt-BR')}</p><p className="text-sm mt-1">Total: <strong>{money(o.total)}</strong>{o.discount>0? ` · Desconto: ${money(o.discount)}`:''}</p><p className="text-xs mt-1">{o.status}</p></div><span className={o.payment_status==='Pago'?'text-sm font-semibold text-success':'text-sm font-semibold text-muted-foreground'}>{o.payment_status==='Pago'?<><CheckCircle2 className="inline size-4 mr-1"/>Pago</>:<><Clock3 className="inline size-4 mr-1"/>Pendente</>}</span>{o.payment_status!=='Pago'&&<Button size="sm" disabled={saving!==null} onClick={()=>void setPaid(o)}>{saving===o.id?'Confirmando...':'Confirmar pagamento'}</Button>}</article>)}{!q.data?.length&&<p className="text-sm text-muted-foreground">Nenhum pedido recebido ainda.</p>}</div></section>;
}
