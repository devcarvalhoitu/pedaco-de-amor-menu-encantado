import {createContext,useContext,useState,type ReactNode} from 'react';
import type {CartItem,Product} from '@/lib/shop-types';
import {toast} from 'sonner';
type CartContextValue={items:CartItem[];open:boolean;setOpen:(v:boolean)=>void;add:(p:Product)=>void;change:(id:string,delta:number)=>void;clear:()=>void};
const CartContext=createContext<CartContextValue|null>(null);
export function CartProvider({children}:{children:ReactNode}) { const [items,setItems]=useState<CartItem[]>([]);const [open,setOpen]=useState(false);return <CartContext.Provider value={{items,open,setOpen,add:p=>{setItems(old=>{const found=old.find(i=>i.product.id===p.id);return found?old.map(i=>i.product.id===p.id?{...i,quantity:Math.min(100,i.quantity+1)}:i):[...old,{product:p,quantity:1}];});toast.success(`${p.name} adicionado ao pedido`);},change:(id,delta)=>setItems(old=>old.map(i=>i.product.id===id?{...i,quantity:Math.min(100,i.quantity+delta)}:i).filter(i=>i.quantity>0)),clear:()=>setItems([])}}>{children}</CartContext.Provider>; }
export function useCart(){const context=useContext(CartContext);if(!context)throw new Error('Carrinho indisponível');return context;}
