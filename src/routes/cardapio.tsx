import {createFileRoute} from '@tanstack/react-router';
import {shopQuery,shopHead} from '@/lib/shop-query';
import {Storefront} from '@/components/storefront';
import {MenuSection} from '@/components/menu';
export const Route=createFileRoute('/cardapio')({loader:({context})=>context.queryClient.ensureQueryData(shopQuery),head:()=>shopHead('Cardápio','Brigadeiros, bolos, tortas e doces artesanais. Escolha seus favoritos e faça seu pedido.'),component:()=> <Storefront><MenuSection/></Storefront>});
