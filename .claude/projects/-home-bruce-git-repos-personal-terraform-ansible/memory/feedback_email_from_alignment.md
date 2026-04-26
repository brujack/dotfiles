---
name: Google Workspace DKIM signing requires From-domain alignment
description: Workspace only signs when From: header domain matches a Workspace domain; external aliases send unsigned
type: feedback
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

Google Workspace only DKIM-signs outbound mail when the `From:` header domain matches a domain
configured in the Workspace account. Sending via a "Send mail as" alias from an external domain
(e.g. `bjackson@pobox.com`) produces unsigned mail (`DKIM = none`) even when DKIM is enabled and
the DNS key is correct.

**Why:** Google signs based on the `From:` domain. External domains aren't owned by the Workspace
account so Google won't sign for them.

**How to apply:** When debugging email authentication failures from a Workspace account:

1. Check the `From:` header in the raw message — not just the envelope sender (Return-Path)
2. If From: is an external domain, the fix is not DNS — use Reply-To for the external address
   and send from the `@conecrazy.ca` address so Workspace signs correctly
3. Port25 verifier (`check-auth@verifier.port25.com`) is the fastest way to see actual
   DKIM/SPF results for a sent message
