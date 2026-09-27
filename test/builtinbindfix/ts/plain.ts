export function tsMapGet(key: string): number | undefined { const table = new Map<string, number>(); return table.get(key); }
