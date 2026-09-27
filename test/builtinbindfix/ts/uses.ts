import { TsPool } from "./pool";
export function tsAnnotated(pool: TsPool, key: string): string { return pool.get(key); }
