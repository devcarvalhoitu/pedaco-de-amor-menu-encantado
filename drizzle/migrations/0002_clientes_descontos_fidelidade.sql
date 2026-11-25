ALTER TABLE public.products ADD COLUMN discount_percent integer NOT NULL DEFAULT 0 CHECK (discount_percent BETWEEN 0 AND 90);
ALTER TABLE public.orders ADD COLUMN customer_id uuid, ADD COLUMN email text NOT NULL DEFAULT '', ADD COLUMN discount numeric NOT NULL DEFAULT 0;
CREATE TABLE public.customers(
 user_id uuid PRIMARY KEY,
 name text NOT NULL DEFAULT '' CHECK (length(name)<=100),
 phone text NOT NULL DEFAULT '' CHECK (length(phone)<=20),
 email text NOT NULL DEFAULT '' CHECK (length(email)<=255),
 address text NOT NULL DEFAULT '' CHECK (length(address)<=500),
 marketing_opt_in boolean NOT NULL DEFAULT false,
 stamps integer NOT NULL DEFAULT 0 CHECK (stamps BETWEEN 0 AND 20),
 reward_percent integer NOT NULL DEFAULT 0 CHECK (reward_percent BETWEEN 0 AND 100),
 created_at timestamptz NOT NULL DEFAULT now());
GRANT SELECT, DELETE ON public.customers TO authenticated;
GRANT INSERT (user_id,name,phone,email,address,marketing_opt_in) ON public.customers TO authenticated;
GRANT UPDATE (name,phone,email,address,marketing_opt_in) ON public.customers TO authenticated;
GRANT UPDATE (stamps,reward_percent) ON public.customers TO authenticated;
GRANT ALL ON public.customers TO service_role;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_read ON public.customers FOR SELECT TO authenticated USING (user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY own_insert ON public.customers FOR INSERT TO authenticated WITH CHECK (user_id=auth.uid());
CREATE POLICY own_update ON public.customers FOR UPDATE TO authenticated USING (user_id=auth.uid() OR public.has_role(auth.uid(),'admin')) WITH CHECK (user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY admin_delete ON public.customers FOR DELETE TO authenticated USING (public.has_role(auth.uid(),'admin'));
CREATE OR REPLACE FUNCTION public.guard_customer_loyalty() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF (NEW.stamps IS DISTINCT FROM OLD.stamps OR NEW.reward_percent IS DISTINCT FROM OLD.reward_percent)
   AND current_user='authenticated' AND NOT public.has_role(auth.uid(),'admin') THEN
   RAISE EXCEPTION 'Somente a administradora altera a fidelidade';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER customers_loyalty_guard BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.guard_customer_loyalty();
CREATE OR REPLACE FUNCTION public.place_order(_request_key uuid, _customer_name text, _phone text, _fulfillment text, _address text, _notes text, _items jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE p public.products; line jsonb; qty integer; unit numeric; result_items jsonb:='[]'; result_total numeric:=0; result_order public.orders; c public.customers; reward numeric:=0;
BEGIN
IF length(trim(_customer_name))<2 OR length(_customer_name)>100 OR _phone !~ '^[0-9+() -]{10,20}$' OR _fulfillment NOT IN('retirada','entrega') OR (_fulfillment='entrega' AND length(trim(_address))<5) OR length(_address)>500 OR length(_notes)>1000 OR jsonb_typeof(_items)<>'array' OR jsonb_array_length(_items)<1 OR jsonb_array_length(_items)>30 THEN RAISE EXCEPTION 'Confira os dados do pedido'; END IF;
SELECT * INTO result_order FROM public.orders WHERE request_key=_request_key;
IF FOUND THEN RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'discount',result_order.discount,'items',result_order.items); END IF;
FOR line IN SELECT value FROM jsonb_array_elements(_items) LOOP
qty:=(line->>'quantity')::integer;
IF qty<1 OR qty>100 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
SELECT * INTO p FROM public.products WHERE id=(line->>'id')::uuid AND available FOR SHARE;
IF NOT FOUND THEN RAISE EXCEPTION 'Um item não está mais disponível'; END IF;
unit:=round(p.price*(100-p.discount_percent)/100.0,2);
result_items:=result_items||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'price',unit,'quantity',qty)); result_total:=result_total+unit*qty;
END LOOP;
IF auth.uid() IS NOT NULL THEN
 SELECT * INTO c FROM public.customers WHERE user_id=auth.uid() FOR UPDATE;
 IF FOUND THEN
  IF c.reward_percent>0 THEN reward:=round(result_total*c.reward_percent/100.0,2); result_total:=result_total-reward; UPDATE public.customers SET stamps=1,reward_percent=0 WHERE user_id=c.user_id;
  ELSE UPDATE public.customers SET stamps=least(20,stamps+1) WHERE user_id=c.user_id; END IF;
 END IF;
END IF;
INSERT INTO public.orders(request_key,customer_name,phone,fulfillment,address,notes,items,total,customer_id,email,discount) VALUES(_request_key,trim(_customer_name),_phone,_fulfillment,_address,_notes,result_items,result_total,c.user_id,coalesce(c.email,''),reward) RETURNING * INTO result_order;
RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'discount',reward,'items',result_order.items);
END $function$;