CREATE TYPE public.app_role AS ENUM ('admin');
CREATE TABLE public.user_roles (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL, role public.app_role NOT NULL, UNIQUE(user_id,role));
GRANT SELECT ON public.user_roles TO authenticated; GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.has_role(_user_id uuid,_role public.app_role) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$ SELECT EXISTS(SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role=_role) $$;
CREATE POLICY own_roles ON public.user_roles FOR SELECT TO authenticated USING(user_id=auth.uid());
CREATE TABLE public.categories (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE, position integer NOT NULL DEFAULT 0);
GRANT SELECT ON public.categories TO anon; GRANT ALL ON public.categories TO authenticated,service_role;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.categories FOR SELECT TO anon,authenticated USING(true);
CREATE POLICY admin_write ON public.categories FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.products (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL, description text NOT NULL DEFAULT '', price numeric(10,2) NOT NULL CHECK(price>=0), category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL, image_url text NOT NULL DEFAULT '', available boolean NOT NULL DEFAULT true, featured boolean NOT NULL DEFAULT false, position integer NOT NULL DEFAULT 0);
GRANT SELECT ON public.products TO anon; GRANT ALL ON public.products TO authenticated,service_role;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_available ON public.products FOR SELECT TO anon,authenticated USING(available);
CREATE POLICY admin_all ON public.products FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.slides (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), title text NOT NULL DEFAULT '', subtitle text NOT NULL DEFAULT '', image_url text NOT NULL, link text NOT NULL DEFAULT '', active boolean NOT NULL DEFAULT true, position integer NOT NULL DEFAULT 0);
GRANT SELECT ON public.slides TO anon; GRANT ALL ON public.slides TO authenticated,service_role;
ALTER TABLE public.slides ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_active ON public.slides FOR SELECT TO anon,authenticated USING(active);
CREATE POLICY admin_all ON public.slides FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.socials (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), network text NOT NULL, url text NOT NULL, position integer NOT NULL DEFAULT 0);
GRANT SELECT ON public.socials TO anon; GRANT ALL ON public.socials TO authenticated,service_role;
ALTER TABLE public.socials ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.socials FOR SELECT TO anon,authenticated USING(true);
CREATE POLICY admin_all ON public.socials FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.settings (id integer PRIMARY KEY DEFAULT 1 CHECK(id=1), name text NOT NULL DEFAULT 'Doce Encanto', tagline text NOT NULL DEFAULT 'Confeitaria artesanal', whatsapp text NOT NULL DEFAULT '', email text NOT NULL DEFAULT '', hours text NOT NULL DEFAULT 'Segunda a sábado · 9h às 18h', address text NOT NULL DEFAULT '', about_title text NOT NULL DEFAULT 'Feito à mão. Com o coração.', about_text text NOT NULL DEFAULT 'Acreditamos que os melhores momentos da vida merecem um toque de doçura. Na nossa cozinha, cada receita leva ingredientes selecionados, cuidado em cada detalhe e uma generosa porção de carinho. Dos brigadeiros de todos os dias aos bolos das grandes celebrações, fazemos tudo artesanalmente para deixar a sua vida mais doce.', about_image text NOT NULL DEFAULT '', logo_url text NOT NULL DEFAULT '', feed_embed text NOT NULL DEFAULT '', feed_links text NOT NULL DEFAULT '', theme text NOT NULL DEFAULT 'rose');
GRANT SELECT ON public.settings TO anon; GRANT ALL ON public.settings TO authenticated,service_role;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY public_read ON public.settings FOR SELECT TO anon,authenticated USING(true);
CREATE POLICY admin_all ON public.settings FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.orders (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), number bigint GENERATED ALWAYS AS IDENTITY UNIQUE, request_key uuid UNIQUE NOT NULL, customer_name text NOT NULL, phone text NOT NULL, fulfillment text NOT NULL CHECK(fulfillment IN('retirada','entrega')), address text NOT NULL DEFAULT '', notes text NOT NULL DEFAULT '', items jsonb NOT NULL, total numeric(10,2) NOT NULL, status text NOT NULL DEFAULT 'Novo' CHECK(status IN('Novo','Em preparo','Pronto','Entregue','Cancelado')), created_at timestamptz NOT NULL DEFAULT now());
GRANT SELECT,UPDATE ON public.orders TO authenticated; GRANT ALL ON public.orders TO service_role;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_read ON public.orders FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin'));
CREATE POLICY admin_update ON public.orders FOR UPDATE TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));
CREATE TABLE public.visits (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT now());
GRANT SELECT ON public.visits TO authenticated; GRANT ALL ON public.visits TO service_role;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_read ON public.visits FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin'));
CREATE INDEX orders_created ON public.orders(created_at); CREATE INDEX visits_created ON public.visits(created_at);
CREATE FUNCTION public.record_visit(_session_id uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$ INSERT INTO public.visits(session_id) VALUES(_session_id) ON CONFLICT(session_id) DO NOTHING $$;
REVOKE ALL ON FUNCTION public.record_visit(uuid) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.record_visit(uuid) TO anon,authenticated;
CREATE FUNCTION public.place_order(_request_key uuid,_customer_name text,_phone text,_fulfillment text,_address text,_notes text,_items jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.products; line jsonb; qty integer; result_items jsonb:='[]'; result_total numeric:=0; result_order public.orders;
BEGIN
IF length(trim(_customer_name))<2 OR length(_customer_name)>100 OR _phone !~ '^[0-9+() -]{10,20}$' OR _fulfillment NOT IN('retirada','entrega') OR (_fulfillment='entrega' AND length(trim(_address))<5) OR length(_address)>500 OR length(_notes)>1000 OR jsonb_typeof(_items)<>'array' OR jsonb_array_length(_items)<1 OR jsonb_array_length(_items)>30 THEN RAISE EXCEPTION 'Confira os dados do pedido'; END IF;
SELECT * INTO result_order FROM public.orders WHERE request_key=_request_key;
IF FOUND THEN RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'items',result_order.items); END IF;
FOR line IN SELECT value FROM jsonb_array_elements(_items) LOOP
qty:=(line->>'quantity')::integer;
IF qty<1 OR qty>100 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
SELECT * INTO p FROM public.products WHERE id=(line->>'id')::uuid AND available FOR SHARE;
IF NOT FOUND THEN RAISE EXCEPTION 'Um item não está mais disponível'; END IF;
result_items:=result_items||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'price',p.price,'quantity',qty)); result_total:=result_total+p.price*qty;
END LOOP;
INSERT INTO public.orders(request_key,customer_name,phone,fulfillment,address,notes,items,total) VALUES(_request_key,trim(_customer_name),_phone,_fulfillment,_address,_notes,result_items,result_total) RETURNING * INTO result_order;
RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'items',result_order.items);
END $$;
REVOKE ALL ON FUNCTION public.place_order(uuid,text,text,text,text,text,jsonb) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.place_order(uuid,text,text,text,text,text,jsonb) TO anon,authenticated;
CREATE FUNCTION public.dashboard_stats(_days integer DEFAULT 7) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public AS $$
DECLARE today timestamptz:=date_trunc('day',now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo'; start_at timestamptz;
BEGIN
IF NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Acesso restrito'; END IF;
IF _days NOT IN(1,7,30) THEN RAISE EXCEPTION 'Período inválido'; END IF;
start_at:=today-make_interval(days=>_days-1);
RETURN jsonb_build_object('today',(SELECT count(*) FROM visits WHERE created_at>=today),'week',(SELECT count(*) FROM visits WHERE created_at>=today-interval '6 days'),'month',(SELECT count(*) FROM visits WHERE created_at>=today-interval '29 days'),'orders',(SELECT count(*) FROM orders),'pending',(SELECT count(*) FROM orders WHERE status IN('Novo','Em preparo','Pronto')),'revenue',(SELECT coalesce(sum(total),0) FROM orders WHERE status='Entregue' AND created_at>=start_at),'daily',(SELECT coalesce(jsonb_agg(r),'[]') FROM (SELECT to_char(d AT TIME ZONE 'America/Sao_Paulo','DD/MM') AS day,(SELECT count(*) FROM visits WHERE created_at>=d AND created_at<d+interval '1 day') AS visits,(SELECT count(*) FROM orders WHERE created_at>=d AND created_at<d+interval '1 day') AS orders FROM generate_series(start_at,today,interval '1 day') d) r),'top',(SELECT coalesce(jsonb_agg(r),'[]') FROM (SELECT item->>'name' AS name,sum((item->>'quantity')::integer) AS quantity FROM orders CROSS JOIN LATERAL jsonb_array_elements(items) item WHERE status<>'Cancelado' AND created_at>=start_at GROUP BY item->>'name' ORDER BY quantity DESC LIMIT 5) r));
END $$;
REVOKE ALL ON FUNCTION public.dashboard_stats(integer) FROM PUBLIC; GRANT EXECUTE ON FUNCTION public.dashboard_stats(integer) TO authenticated;
CREATE POLICY admin_images ON storage.objects FOR ALL TO authenticated USING(bucket_id='confeitaria' AND public.has_role(auth.uid(),'admin')) WITH CHECK(bucket_id='confeitaria' AND public.has_role(auth.uid(),'admin'));
INSERT INTO public.categories(id,name,position) VALUES ('00000000-0000-4000-8000-000000000001','Brigadeiros',0),('00000000-0000-4000-8000-000000000002','Bolos',1),('00000000-0000-4000-8000-000000000003','Tortas',2),('00000000-0000-4000-8000-000000000004','Docinhos',3),('00000000-0000-4000-8000-000000000005','Salgados',4);
INSERT INTO public.products(name,description,price,category_id,image_url,featured,position) VALUES
('Brigadeiro clássico','Chocolate de verdade, granulado belga e muito carinho. Unidade.',4.5,'00000000-0000-4000-8000-000000000001','/__l5e/assets-v1/e6672e3b-d1bd-4f85-b186-1efb2b203fb5/brigadeiro.webp',true,0),
('Bolo de morango','Massa fofinha, creme de baunilha e morangos frescos. 1 kg.',89.9,'00000000-0000-4000-8000-000000000002','/__l5e/assets-v1/400ebf4f-3dfa-42e3-9900-ae839b41ba3f/bolo.webp',true,1),
('Torta de limão','O equilíbrio perfeito entre o azedinho e o doce. Unidade.',18.9,'00000000-0000-4000-8000-000000000003','/__l5e/assets-v1/fdaa52ba-813c-4ee2-b445-911d6d01a91b/torta.webp',true,2),
('Brigadeiro de morango','Delicado, cremoso e feito com morangos selecionados. Unidade.',5,'00000000-0000-4000-8000-000000000004','/__l5e/assets-v1/4d410b73-33a6-4924-8633-a0887d53620d/docinho.webp',true,3),
('Brownie de chocolate','Casquinha crocante e um coração de chocolate com nozes.',12.9,'00000000-0000-4000-8000-000000000004','/__l5e/assets-v1/c6041450-7e5d-4b9f-8537-79ec89ce6b4c/brownie.webp',false,4),
('Coxinha artesanal','Massa douradinha e recheio cremoso de frango. Unidade.',7.5,'00000000-0000-4000-8000-000000000005','/__l5e/assets-v1/ba8cd6f4-f912-4714-b6f3-bda9a84ec878/coxinha.webp',false,5),
('Caixa de brigadeiros','Uma caixa de carinho com 12 brigadeiros clássicos.',48,'00000000-0000-4000-8000-000000000001','/__l5e/assets-v1/e6672e3b-d1bd-4f85-b186-1efb2b203fb5/brigadeiro.webp',false,6),
('Caixa de docinhos rosa','12 docinhos de morango para compartilhar momentos doces.',54,'00000000-0000-4000-8000-000000000004','/__l5e/assets-v1/4d410b73-33a6-4924-8633-a0887d53620d/docinho.webp',false,7);
INSERT INTO public.slides(title,subtitle,image_url,position) VALUES ('Doce Encanto','Pequenos doces. Grandes momentos.','/__l5e/assets-v1/d6475045-191c-4a1b-9997-ff99e361d366/confeitaria-hero.png',0),('Carinho em cada receita','Feito à mão, para celebrar com você.','/__l5e/assets-v1/ba1c13e3-0f0d-47c0-af8f-289a648ee0a6/confeitaria-about.png',1),('Um pedacinho de felicidade','Seu doce favorito está aqui.','/__l5e/assets-v1/400ebf4f-3dfa-42e3-9900-ae839b41ba3f/bolo.webp',2);
INSERT INTO public.socials(network,url,position) VALUES ('Instagram','https://www.instagram.com/',0),('Facebook','https://www.facebook.com/',1);
INSERT INTO public.settings(id,about_image) VALUES(1,'/__l5e/assets-v1/ba1c13e3-0f0d-47c0-af8f-289a648ee0a6/confeitaria-about.png');