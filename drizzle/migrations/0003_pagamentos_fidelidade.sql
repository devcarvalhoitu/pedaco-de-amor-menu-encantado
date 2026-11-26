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
    IF NEW.discount > 0 THEN
      -- O benefício foi utilizado neste pedido: inicia um novo cartão.
      UPDATE public.customers SET stamps = 0 WHERE user_id = NEW.customer_id;
    ELSE
      -- place_order já contabiliza o pedido; desfazemos aqui até a confirmação do pagamento.
      UPDATE public.customers SET stamps = greatest(0, stamps - 1) WHERE user_id = NEW.customer_id;
    END IF;
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
     AND NEW.discount = 0
     AND NEW.status <> 'Cancelado' THEN
    UPDATE public.customers
      SET stamps = least(20, stamps + 1)
      WHERE user_id = NEW.customer_id;
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
