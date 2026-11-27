export function loyaltyDiscount(subtotal:number,customer:{stamps:number;reward_percent:number}) {
  if(customer.stamps<20||customer.reward_percent<=0)return 0;
  return Math.round(subtotal*Math.min(customer.reward_percent,100))/100;
}