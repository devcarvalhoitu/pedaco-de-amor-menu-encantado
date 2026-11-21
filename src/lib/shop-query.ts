import {queryOptions} from '@tanstack/react-query';
import {getShop} from './shop.functions';
export const shopQuery=queryOptions({queryKey:['shop'],queryFn:()=>getShop(),staleTime:15000,refetchInterval:15000});
export function shopHead(title:string,description:string) { return {meta:[{title:`${title} | Doce Encanto`},{name:'description',content:description},{property:'og:title',content:`${title} | Doce Encanto`},{property:'og:description',content:description},{property:'og:type',content:'website'},{name:'twitter:card',content:'summary_large_image'}]}; }
