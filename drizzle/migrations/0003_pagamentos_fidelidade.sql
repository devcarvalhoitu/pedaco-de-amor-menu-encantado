-- Pagamento manual e fidelidade: selos são concedidos somente quando o admin confirma o pagamento.
ALTER TABLE public.orders
  ADD COLUMN payment_status text NOT NULL DEFAULT 'Pendente'
  CHECK (payment_status IN ('Pendente','Pago'));

GRANT SELECT ON public.orders TO authenticated;
GRANT UPDATE (payment_status) ON public.orders TO authenticated;

CREATE POLICY customer_read_own_orders
  ON public.orders FOR SELECT TO authenticated
  USING (customer_id = auth.uid() OR public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.sync_order_loyalty_on_create()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL THEN
    -- Nenhum selo é concedido ou removido antes da confirmação do pagamento.
    NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER orders_loyalty_pending
AFTER INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.sync_order_loyalty_on_create();

CREATE OR REPLACE FUNCTION public.confirm_order_payment_loyalty()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF OLD.payment_status IS DISTINCT FROM NEW.payment_status
     AND NEW.payment_status = 'Pago'
     AND NEW.customer_id IS NOT NULL
     AND NEW.status <> 'Cancelado' THEN
    IF NEW.discount > 0 THEN
      UPDATE public.customers SET stamps = 0, reward_percent = 0 WHERE user_id = NEW.customer_id;
    ELSE
      UPDATE public.customers SET stamps = least(20, stamps + 1) WHERE user_id = NEW.customer_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER orders_payment_loyalty
AFTER UPDATE OF payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.confirm_order_payment_loyalty();

-- Somente administradores podem alterar o estado do pagamento.
CREATE OR REPLACE FUNCTION public.guard_order_payment_status()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
     AND NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Somente a administradora pode confirmar pagamentos';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER orders_payment_guard
BEFORE UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.guard_order_payment_status();

-- Substitui a função original: reservar o desconto no pedido, mas só consumir o benefício
-- quando o pagamento for confirmado pelo painel.
CREATE OR REPLACE FUNCTION public.place_order(_request_key uuid, _customer_name text, _phone text, _fulfillment text, _address text, _notes text, _items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  result_items:=result_items||jsonb_build_array(jsonb_build_object('id',p.id,'name',p.name,'price',unit,'quantity',qty));
  result_total:=result_total+unit*qty;
 END LOOP;
 IF auth.uid() IS NOT NULL THEN
  SELECT * INTO c FROM public.customers WHERE user_id=auth.uid() FOR UPDATE;
  IF FOUND AND c.reward_percent>0 AND c.stamps>=20 THEN
   reward:=round(result_total*c.reward_percent/100.0,2);
   result_total:=result_total-reward;
   -- O benefício foi aplicado neste pedido: o cartão reinicia uma única vez.
   UPDATE public.customers SET stamps=0,reward_percent=0 WHERE user_id=c.user_id;
  END IF;
 END IF;
 INSERT INTO public.orders(request_key,customer_name,phone,fulfillment,address,notes,items,total,customer_id,email,discount)
 VALUES(_request_key,trim(_customer_name),_phone,_fulfillment,_address,_notes,result_items,result_total,c.user_id,coalesce(c.email,''),reward)
 RETURNING * INTO result_order;
 RETURN jsonb_build_object('number',result_order.number,'total',result_order.total,'discount',reward,'items',result_order.items);
END $function$;
