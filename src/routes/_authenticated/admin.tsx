import {createFileRoute,redirect} from '@tanstack/react-router';
import {supabase} from '@/integrations/supabase/client';
import {canAccessAdmin} from '@/lib/admin-access';
import {shopHead} from '@/lib/shop-query';
import {AdminDashboard} from '@/components/admin-dashboard';
export const Route=createFileRoute('/_authenticated/admin')({beforeLoad:async()=>{const {data,error}=await supabase.from('user_roles').select('role');if(error||!canAccessAdmin(data??[]))throw redirect({to:'/auth'});},head:()=>shopHead('Painel da confeitaria','Gerencie a logo e as imagens do carrossel da Pedaços de amor gourmet.'),component:AdminDashboard});
