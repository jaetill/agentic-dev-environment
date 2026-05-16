/**
 * Readiness endpoint per ADR-0009 §7.
 * Returns 200 if ready to serve traffic (deps reachable, migrations applied).
 *
 * Add real readiness checks (DB connectivity, deps reachable) as the project grows.
 */

import { NextResponse } from 'next/server';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET() {
  // TODO: add real readiness checks as project grows. Examples:
  //   - DB connectivity: await db.execute(sql`select 1`)
  //   - External service health: await fetch(externalService + '/health')
  //
  // For now, parity with /health
  return NextResponse.json({ status: 'ready' });
}
