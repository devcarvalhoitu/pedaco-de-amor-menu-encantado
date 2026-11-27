ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'Pendente' CHECK (payment_status IN ('Pendente','Pago'));
GRANT SELECT ON public.orders TO authenticated;
GRANT UPDATE (payment_status) ON public.orders TO authenticated;
CREATE POLICY customer_read_own_orders ON public.orders FOR SELECT TO authenticated USING (customer_id = auth.uid());

CREATE OR REPLACE FUNCTION public.guard_customer_loyalty()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF current_user IN ('authenticated','anon') THEN
  IF TG_OP='INSERT' THEN
   IF NEW.stamps<>0 OR NEW.reward_percent<>0 THEN RAISE EXCEPTION 'O cartão começa sem selos e sem desconto'; END IF;
  ELSE
   IF NEW.stamps IS DISTINCT FROM OLD.stamps THEN RAISE EXCEPTION 'Os selos são atualizados automaticamente pelos pedidos'; END IF;
   IF NEW.reward_percent IS DISTINCT FROM OLD.reward_percent AND (NOT public.has_role(auth.uid(),'admin') OR NEW.stamps<20 OR NEW.reward_percent<0 OR NEW.reward_percent>100) THEN RAISE EXCEPTION 'Somente a administradora libera desconto para um cartão com 20 selos'; END IF;
  END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER customers_initial_loyalty_guard BEFORE INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION public.guard_customer_loyalty();

CREATE OR REPLACE FUNCTION public.guard_order_payment_status()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Somente a administradora pode confirmar pagamentos'; END IF;
 IF OLD.payment_status='Pago' AND NEW.payment_status<>'Pago' THEN RAISE EXCEPTION 'O pagamento já foi confirmado'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER orders_payment_guard BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.guard_order_payment_status();

CREATE OR REPLACE FUNCTION public.place_order(_request_key uuid, _customer_name text, _phone text, _fulfillment text, _address text, _notes text, _items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.products; line jsonb; qty integer; unit numeric; result_items jsonb:='[]'; result_total numeric:=0; result_order public.orders; c public.customers; reward numeric:=0; submitted_name text:=_customer_name; submitted_phone text:=_phone; submitted_address text:=_address;
BEGIN
 IF _request_key IS NULL THEN RAISE EXCEPTION 'Confira os dados do pedido'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_request_key::text,0));
 SELECT * INTO result_order FROM public.orders WHERE request_key=_request_key;
 IF FOUND THEN
  IF result_order.customer_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Este pedido pertence a outro cliente'; END IF;
  RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'discount',result_order.discount,'payment_status',result_order.payment_status,'items',result_order.items);
 END IF;
 IF auth.uid() IS NOT NULL THEN
  SELECT * INTO c FROM public.customers WHERE user_id=auth.uid() FOR UPDATE;
  IF FOUND THEN
   submitted_name:=coalesce(nullif(trim(submitted_name),''),c.name);
   submitted_phone:=coalesce(nullif(trim(submitted_phone),''),c.phone);
   submitted_address:=coalesce(nullif(trim(submitted_address),''),c.address);
  END IF;
 END IF;
 IF submitted_name IS NULL OR length(trim(submitted_name))<2 OR length(submitted_name)>100 OR submitted_phone IS NULL OR submitted_phone !~ '^[0-9+() -]{10,20}$' OR _fulfillment IS NULL OR _fulfillment NOT IN('retirada','entrega') OR submitted_address IS NULL OR (_fulfillment='entrega' AND length(trim(submitted_address))<5) OR length(submitted_address)>500 OR _notes IS NULL OR length(_notes)>1000 OR _items IS NULL OR jsonb_typeof(_items)<>'array' THEN RAISE EXCEPTION 'Confira os dados do pedido'; END IF;
 IF jsonb_array_length(_items)<1 OR jsonb_array_length(_items)>30 THEN RAISE EXCEPTION 'Confira os itens do pedido'; END IF;
 FOR line IN SELECT value FROM jsonb_array_elements(_items) LOOP
  IF (line->>'quantity') IS NULL OR (line->>'quantity') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
  qty:=(line->>'quantity')::integer;
  IF qty<1 OR qty>100 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
  SELECT * INTO p FROM public.products WHERE id=(line->>'id')::uuid AND available FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Um item não está mais disponível'; END IF;
  unit:=round(p.price*(100-p.discount_percent)/100.0,2);
  result_items:=result_items||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'price',unit,'quantity',qty));
  result_total:=result_total+unit*qty;
 END LOOP;
 IF c.user_id IS NOT NULL AND c.stamps>=20 AND c.reward_percent>0 THEN
  reward:=round(result_total*c.reward_percent/100.0,2);
  IF reward>0 THEN result_total:=result_total-reward; END IF;
 END IF;
 INSERT INTO public.orders(request_key,customer_name,phone,fulfillment,address,notes,items,total,customer_id,email,discount)
 VALUES(_request_key,trim(submitted_name),submitted_phone,_fulfillment,submitted_address,_notes,result_items,result_total,c.user_id,coalesce(c.email,''),reward) RETURNING * INTO result_order;
 IF c.user_id IS NOT NULL THEN
  IF reward>0 THEN UPDATE public.customers SET stamps=1,reward_percent=0 WHERE user_id=c.user_id;
  ELSE UPDATE public.customers SET stamps=least(20,stamps+1) WHERE user_id=c.user_id; END IF;
 END IF;
 RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'discount',reward,'payment_status',result_order.payment_status,'items',result_order.items);
END $$;