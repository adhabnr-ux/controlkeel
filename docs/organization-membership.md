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
