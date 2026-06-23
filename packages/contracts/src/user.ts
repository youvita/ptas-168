import { z } from 'zod'
import { UserRoleSchema, UserStatusSchema, AuthViaSchema } from './enums.js'

// Auth — write inputs ───────────────────────────────────────────────────────

export const loginCredentialsSchema = z
  .object({
    username: z.string().min(1, 'Username is required'),
    password: z.string().min(1, 'Password is required'),
  })
  .strict()
export type LoginCredentialsInput = z.infer<typeof loginCredentialsSchema>

export const registerSchema = z
  .object({
    username: z.string().min(3).max(40).regex(/^[a-zA-Z0-9_-]+$/, 'Use letters, numbers, _ or -'),
    fullName: z.string().min(1).max(120),
    phone: z.string().min(3).max(40).optional(),
    password: z.string().min(6),
  })
  .strict()
export type RegisterInput = z.infer<typeof registerSchema>

export const loginTelegramSchema = z
  .object({
    initData: z.string().min(1, 'initData is required'),
  })
  .strict()
export type LoginTelegramInput = z.infer<typeof loginTelegramSchema>

export const updateProfileSchema = z
  .object({
    fullName: z.string().min(1).optional(),
    username: z.string().min(3).max(40).regex(/^[a-zA-Z0-9_-]+$/, 'Use letters, numbers, _ or -').optional(),
    phone: z.string().optional().nullable(),
    profileImage: z.string().optional().nullable(),
  })
  .strict()
export type UpdateProfileInput = z.infer<typeof updateProfileSchema>

export const changePasswordSchema = z
  .object({
    currentPassword: z.string().min(1),
    newPassword: z.string().min(6),
  })
  .strict()
export type ChangePasswordInput = z.infer<typeof changePasswordSchema>

// Sub-user CRUD — owner/manager only ────────────────────────────────────────

// On the wire, write payloads use `active: boolean` and `fullName`. The
// response DTO uses `status: 'active'|'inactive'` and `name`. See the
// asymmetric-shape note in MIGRATION_ANALYSIS.md §5.
const SubUserRoleSchema = z.enum(['manager', 'staff', 'viewer'])

export const createUserSchema = z
  .object({
    username: z.string().min(1).max(60),
    fullName: z.string().min(1).max(120),
    password: z.string().min(6).max(120),
    phone: z.string().min(3).max(40).optional().nullable(),
    role: SubUserRoleSchema.default('staff'),
    active: z.boolean().default(true),
  })
  .strict()
export type CreateUserInput = z.infer<typeof createUserSchema>

export const updateUserSchema = z
  .object({
    fullName: z.string().min(1).max(120).optional(),
    phone: z.string().min(3).max(40).optional().nullable(),
    role: SubUserRoleSchema.optional(),
    active: z.boolean().optional(),
    password: z.string().min(6).max(120).optional(),
  })
  .strict()
export type UpdateUserInput = z.infer<typeof updateUserSchema> 

// Read DTO + JWT payload ────────────────────────────────────────────────────

export const UserDtoSchema = z.object({
  id: z.string(),
  name: z.string(),               // NB: maps from DB column `fullName`
  username: z.string(),
  phone: z.string().nullable(),
  profileImage: z.string().nullable(),
  role: UserRoleSchema,
  status: UserStatusSchema,
  via: AuthViaSchema,
  createdAt: z.string(),
})
export type UserDto = z.infer<typeof UserDtoSchema>

// JWT payload as signed by apps/backend/src/utils/jwt.ts. `telegramId` is
// a string here even though Prisma stores BigInt — JSON cannot represent
// integers above 2^53 safely, so the JWT serializer emits strings.
export const JwtPayloadSchema = z.object({
  userId: z.string(),
  role: z.string(),
  telegramId: z.string().optional(),
})
export type JwtPayload = z.infer<typeof JwtPayloadSchema>

export const AuthResponseSchema = z.object({
  token: z.string(),
  user: UserDtoSchema,
})
export type AuthResponse = z.infer<typeof AuthResponseSchema>
