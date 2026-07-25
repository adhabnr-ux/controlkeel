# Organization Membership

## Invitation Flow

```
Admin/Owner invites by email
    → User record created (if new)
    → Membership: status=pending, invitation_token_hash=set
    → Raw token shown once + emailed

Invitee opens /invitations/:token
    → Sees org name + role
    → Not authenticated → "Continue with Google/GitHub"
    → OAuth → redirected back to invitation page
    → Email matches → "Accept"
    → status=active, token_hash=cleared, accepted_at=stamped
```

- Token is 256-bit random, stored as SHA-256 hash (not reversible).
- Token hash is cleared on both accept and revoke.
- Acceptance requires OAuth — token proves _what_ (org + role), OAuth proves _who_ (email).

## Re-inviting Revoked Members

| Existing state       | Behavior                           |
| -------------------- | ---------------------------------- |
| None                 | INSERT new pending membership      |
| `revoked`            | UPDATE to pending with fresh token |
| `active` / `pending` | `{:error, :already_member}`        |

## Revoke Rules

| Who is being revoked | Owner can revoke? | Admin can revoke? | Member can revoke? | Viewer can revoke? |
| -------------------- | ----------------- | ----------------- | ------------------ | ------------------ |
| Owner                | Yes\*             | No                | No                 | No                 |
| Admin                | Yes               | No                | No                 | No                 |
| Member               | Yes               | Yes               | No                 | No                 |
| Viewer               | Yes               | Yes               | No                 | No                 |

\*Owner cannot revoke self if they are the last owner.

Enforced at two layers: UI (`can_revoke?/3`) hides the button, server (`revoke_membership/2`) rejects unauthorized calls.

## Role Change Rules

Server enforcement lives in `update_membership_role/3` (`accounts.ex`). The UI never disables the dropdown. Client-side validation (a `RoleSelect` JS hook) blocks disallowed changes with a native browser `alert()` **before** any request reaches the server — the select reverts to its original value so the UI never shows an invalid state. The server is still the source of truth and rejects anything the hook misses.

### Matrix

| Revoker  | Self                           | Other owner               | Other admin               | Member / Viewer           |
| -------- | ------------------------------ | ------------------------- | ------------------------- | ------------------------- |
| Owner    | Any role, except if last owner | Any role                  | Any role                  | Any role                  |
| Admin    | Demote to member/viewer only   | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | member or viewer only     |
| Member   | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |
| Viewer   | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |
| Outsider | Blocked (`:unauthorized`)      | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) | Blocked (`:unauthorized`) |

### Rules

1. **Only admins and owners see the role dropdown.** Members/viewers see the role as plain text (`@can_manage` is `false`).
2. **Only owners can grant admin or owner.** Admins cannot promote anyone (including self) to admin or owner.
3. **Admins can demote themselves** to member or viewer, but cannot otherwise touch other admins or owners.
4. **Admins can move members/viewers laterally** between the member and viewer roles only.
5. **The last active owner is protected.** An owner cannot demote themself if no other active owner exists (`:last_owner_protected`). Promote another member first, then demote.
6. **No-op selections are allowed.** Selecting the current role succeeds without error (does not trigger promotion checks).
7. **Client-side guard.** A `RoleSelect` hook intercepts the `<select>` change event and validates against the same matrix using data attributes (`data-viewer-role`, `data-target-role`, `data-is-self`, `data-is-last-owner`). Disallowed selections trigger a native `alert()` and the select reverts — no server round-trip, no UI flicker. The server still enforces all rules as the authoritative layer.

### Error Codes

| Error                   | Cause                                                                |
| ----------------------- | -------------------------------------------------------------------- |
| `:unauthorized`         | Revoker lacks permission for the target or new role.                 |
| `:last_owner_protected` | Owner attempted to demote self while they are the last active owner. |
| `:invalid_role`         | `new_role` is not one of `owner`, `admin`, `member`, `viewer`.       |
| `:not_found`            | `membership_id` does not exist.                                      |
