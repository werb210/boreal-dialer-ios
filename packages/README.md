# packages

## Removed: dialer-web (v184)

`packages/dialer-web` was a second, browser-based dialer. Nothing ever loaded
it: CI built and tested it on every push, there was no deploy step for it in
the only workflow, and BF-portal has its own Twilio Device dialer at
`src/dialer/` (`DialerProvider.tsx`, `api.ts`, `store.ts`) that is what
staff.boreal.financial actually runs.

Blocks v147, v149, v154, v156 and v161 all shipped into it and reached no user.
Do not re-add a web dialer here. Portal dialer changes belong in BF-portal.
