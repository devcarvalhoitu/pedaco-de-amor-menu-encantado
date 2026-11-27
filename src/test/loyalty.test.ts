import {describe,it,expect} from 'vitest';
import {loyaltyDiscount} from '@/lib/loyalty';
describe('desconto fidelidade',()=>{
  it('não libera desconto antes de completar 20 selos',()=>expect(loyaltyDiscount(100,{stamps:19,reward_percent:25})).toBe(0));
  it('usa a porcentagem escolhida pela administradora com 20 selos',()=>expect(loyaltyDiscount(100,{stamps:20,reward_percent:25})).toBe(25));
  it('aguarda a administradora liberar o desconto',()=>expect(loyaltyDiscount(100,{stamps:20,reward_percent:0})).toBe(0));
});