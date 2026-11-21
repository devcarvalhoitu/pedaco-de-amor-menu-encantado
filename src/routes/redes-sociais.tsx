import {createFileRoute} from '@tanstack/react-router';
import {shopQuery,shopHead} from '@/lib/shop-query';
import {Storefront} from '@/components/storefront';
import {SocialSection} from '@/components/public-sections';
export const Route=createFileRoute('/redes-sociais')({loader:({context})=>context.queryClient.ensureQueryData(shopQuery),head:()=>shopHead('Redes sociais','Acompanhe as novidades, os doces e os bastidores da nossa confeitaria.'),component:()=> <Storefront><SocialSection full/></Storefront>});
