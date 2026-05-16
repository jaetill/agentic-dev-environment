/**
 * Factory data generators per ADR-0006 §6 and ADR-0004.
 *
 * Use fishery to generate synthetic test data. Production data must NEVER
 * be used in non-prod environments (per ADR-0006).
 *
 * Example:
 *
 *     import { Factory } from 'fishery';
 *     import type { User } from '@/lib/db/schema';
 *
 *     export const userFactory = Factory.define<User>(({ sequence }) => ({
 *       id: sequence,
 *       email: `alice${sequence}@example.test`,
 *       displayName: `Alice ${sequence}`,
 *       createdAt: new Date(),
 *     }));
 */

export {};
