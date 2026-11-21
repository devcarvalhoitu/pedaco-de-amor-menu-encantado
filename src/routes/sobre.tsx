import {createFileRoute} from '@tanstack/react-router';
import {shopQuery,shopHead} from '@/lib/shop-query';
import {Storefront} from '@/components/storefront';
import {AboutSection} from '@/components/public-sections';
export const Route=createFileRoute('/sobre')({loader:({context})=>context.queryClient.ensureQueryData(shopQuery),head:()=>shopHead('Nossa história','Conheça o carinho e os ingredientes por trás dos nossos doces artesanais.'),component:()=> <Storefront><div className="page-intro"><p className="section-kicker">Carinho que vira receita</p><h1 className="page-title">Nossa história</h1></div><AboutSection full/></Storefront>});
