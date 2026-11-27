import {describe,it,expect} from 'vitest';
import postgres from 'postgres';

const url=process.env['SUPABASE_DB_URL'];
describe.skipIf(!url)('regras de pedidos no banco (transações revertidas)',()=>{
 async function scenario(run:(sql:postgres.TransactionSql,uid:string,productId:string)=>Promise<void>){
  if(!url)throw new Error('Conexão de teste indisponível');
  const db=postgres(url,{max:1});const rollback=new Error('rollback-test');
  try{await db.begin(async sql=>{
   const uid=crypto.randomUUID();
   const products=await sql`insert into public.products(name,price,discount_percent) values('Teste transacional',100,10) returning id`;
   const productId=products[0]?.['id'];if(typeof productId!=='string')throw new Error('Produto não encontrado');
   await sql`insert into public.customers(user_id,name,phone,address) values(${uid},'Cliente teste','11999999999','Rua Teste, 10')`;
   await run(sql,uid,productId);throw rollback;
  });}catch(error){if(error!==rollback)throw error;}finally{await db.end();}
 }
 async function identity(sql:postgres.TransactionSql,uid:string){await sql`select set_config('request.jwt.claim.sub',${uid},true)`;}
 async function order(sql:postgres.TransactionSql,id:string,key=crypto.randomUUID()){
  const rows=await sql`select public.place_order(${key}::uuid,'','','entrega','','',${JSON.stringify([{id,quantity:1}])}::jsonb) as result`;
  return {key,result:rows[0]?.['result'] as {number:number;total:number;discount:number;payment_status:string}};
 }
 it('ganha 1 selo ao pedir, usa os dados salvos e não duplica na repetição',async()=>scenario(async(sql,uid,p)=>{
  await identity(sql,uid);const first=await order(sql,p);await order(sql,p,first.key);
  const rows=await sql`select stamps from public.customers where user_id=${uid}`;expect(rows[0]?.['stamps']).toBe(1);
  expect(first.result.payment_status).toBe('Pendente');expect(first.result.total).toBe(90);
  const orders=await sql`select customer_name,address from public.orders where request_key=${first.key}`;
  expect(orders[0]?.['customer_name']).toBe('Cliente teste');expect(orders[0]?.['address']).toBe('Rua Teste, 10');
 }));
 it('completa 20 selos e mantém o cartão cheio enquanto aguarda o desconto',async()=>scenario(async(sql,uid,p)=>{
  await identity(sql,uid);for(let i=0;i<21;i++)await order(sql,p);
  const rows=await sql`select stamps,reward_percent from public.customers where user_id=${uid}`;
  expect(rows[0]?.['stamps']).toBe(20);expect(rows[0]?.['reward_percent']).toBe(0);
 }));
 it('desconto de 25% autorizado para 20 selos é consumido uma única vez',async()=>scenario(async(sql,uid,p)=>{
  const rewarded=crypto.randomUUID();
  await sql`insert into public.customers(user_id,name,phone,address,stamps,reward_percent) values(${rewarded},'Cliente teste','11999999999','Rua Teste, 10',20,25)`;
  await identity(sql,rewarded);const redeemed=await order(sql,p);await order(sql,p,redeemed.key);
  expect(redeemed.result.discount).toBe(22.5);expect(redeemed.result.total).toBe(67.5);
  const rows=await sql`select stamps,reward_percent from public.customers where user_id=${rewarded}`;expect(rows[0]?.['stamps']).toBe(1);expect(rows[0]?.['reward_percent']).toBe(0);
  const next=await order(sql,p);expect(next.result.discount).toBe(0);
 }));
 it('outro cliente não pode recuperar o pedido pela chave de repetição',async()=>scenario(async(sql,uid,p)=>{
  await identity(sql,uid);const first=await order(sql,p);await identity(sql,crypto.randomUUID());
  let blocked=false;try{await sql.savepoint(async tx=>{await order(tx,p,first.key);});}catch{blocked=true;}expect(blocked).toBe(true);
 }));
});