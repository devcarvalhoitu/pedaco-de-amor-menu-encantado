-- Corrige o fluxo de fidelidade: o pedido registra 1 selo ao ser criado;
-- o pagamento continua pendente até a confirmação da administradora.
-- Um desconto reservado só é consumido quando o pedido com desconto for pago.

DROP TRIGGER IF EXISTS orders_loyalty_pending ON public.orders;
DROP TRIGGER IF EXISTS orders_payment_loyalty ON public.orders;

CREATE OR REPLACE FUNCTION public.add_stamp_when_order_is_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.customer_id IS NOT NULL AND NEW.status <> 'Cancelado' THEN
    UPDATE public.customers
       SET stamps = least(20, stamps + 1)
     WHERE user_id = NEW.customer_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER orders_add_stamp_on_create
AFTER INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.add_stamp_when_order_is_created();

CREATE OR REPLACE FUNCTION public.confirm_order_payment_loyalty()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.payment_status IS DISTINCT FROM NEW.payment_status
     AND NEW.payment_status = 'Pago'
     AND NEW.customer_id IS NOT NULL
     AND NEW.status <> 'Cancelado'
     AND NEW.discount > 0 THEN
    UPDATE public.customers
       SET stamps = 0, reward_percent = 0
     WHERE user_id = NEW.customer_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER orders_payment_loyalty
AFTER UPDATE OF payment_status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.confirm_order_payment_loyalty();

-- Nova versão do RPC: não zera os selos no momento da criação do pedido.
CREATE OR REPLACE FUNCTION public.place_order_v2(
  _request_key uuid,
  _customer_name text,
  _phone text,
  _fulfillment text,
  _address text,
  _notes text,
  _items jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  p public.products;
  line jsonb;
  qty integer;
  unit numeric;
  result_items jsonb := '[]';
  result_total numeric := 0;
  result_order public.orders;
  c public.customers;
  reward numeric := 0;
BEGIN
  IF length(trim(_customer_name)) < 2 OR length(_customer_name) > 100
     OR _phone !~ '^[0-9+() -]{10,20}$'
     OR _fulfillment NOT IN ('retirada','entrega')
     OR (_fulfillment = 'entrega' AND length(trim(_address)) < 5)
     OR length(_address) > 500 OR length(_notes) > 1000
     OR jsonb_typeof(_items) <> 'array'
     OR jsonb_array_length(_items) < 1 OR jsonb_array_length(_items) > 30 THEN
    RAISE EXCEPTION 'Confira os dados do pedido';
  END IF;

  SELECT * INTO result_order FROM public.orders WHERE request_key = _request_key;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'number', result_order.number,
      'total', result_order.total,
      'discount', result_order.discount,
      'items', result_order.items
    );
  END IF;

  FOR line IN SELECT value FROM jsonb_array_elements(_items) LOOP
    qty := (line->>'quantity')::integer;
    IF qty < 1 OR qty > 100 THEN RAISE EXCEPTION 'Quantidade inválida'; END IF;
    SELECT * INTO p FROM public.products
      WHERE id = (line->>'id')::uuid AND available FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Um item não está mais disponível'; END IF;
    unit := round(p.price * (100 - p.discount_percent) / 100.0, 2);
    result_items := result_items || jsonb_build_array(
      jsonb_build_object('id', p.id, 'name', p.name, 'price', unit, 'quantity', qty)
    );
    result_total := result_total + unit * qty;
  END LOOP;

  IF auth.uid() IS NOT NULL THEN
    SELECT * INTO c FROM public.customers WHERE user_id = auth.uid() FOR UPDATE;
    IF FOUND AND c.reward_percent > 0 AND c.stamps >= 20 THEN
      IF EXISTS (
        SELECT 1 FROM public.orders
         WHERE customer_id = c.user_id
           AND discount > 0
           AND payment_status = 'Pendente'
           AND status <> 'Cancelado'
      ) THEN
        RAISE EXCEPTION 'Você já tem um desconto reservado em um pedido pendente. Aguarde a confirmação do pagamento.';
      END IF;
      reward := round(result_total * c.reward_percent / 100.0, 2);
      result_total := result_total - reward;
      -- Não zera o cartão aqui. A baixa acontece quando o pagamento for confirmado.
    END IF;
  END IF;

  INSERT INTO public.orders(
    request_key, customer_name, phone, fulfillment, address, notes,
    items, total, customer_id, email, discount, payment_status
  )
  VALUES(
    _request_key, trim(_customer_name), _phone, _fulfillment, _address, _notes,
    result_items, result_total, c.user_id, coalesce(c.email, ''), reward, 'Pendente'
  )
  RETURNING * INTO result_order;

  RETURN jsonb_build_object(
    'number', result_order.number,
    'total', result_order.total,
    'discount', reward,
    'items', result_order.items
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_order_v2(uuid,text,text,text,text,text,jsonb) TO anon, authenticated;
