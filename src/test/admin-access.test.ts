import {describe,it,expect} from 'vitest';
import {canAccessAdmin} from '@/lib/admin-access';
describe('administrative access',()=>{
 it('allows the registered administrator',()=>expect(canAccessAdmin([{role:'admin'}])).toBe(true));
 it('denies customers without an administrative role',()=>expect(canAccessAdmin([])).toBe(false));
 it('denies a non-administrative role',()=>expect(canAccessAdmin([{role:'customer'}])).toBe(false));
});
