export function canAccessAdmin(roles: readonly {role:string}[]) { return roles.some(row=>row.role==='admin'); }
