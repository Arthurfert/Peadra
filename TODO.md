# TODO

**The application is not intended to become cloud-based, and will stay local.**

> [!NOTE]
> An API access to your bank either need a approval from an organization, or isn't free (services like Plaid). It is thus not possible.

## Currently in development

### New

- You can now click on the "others" section of a pie chart to unveil all categories
- The assets distribution pie chart is now double layered : global account types into details
- New setting : Hide update notifications
- New backup policy in order to keep one from yersteday and one from last week, plus the 3 last app opening

### Fixes

- Fixed the assets distribution pie chart taking future transactions
- Transactions are now sorted by last edit per day (fixing the previous odd order)
- Fixed the description proposals in transaction modals to fetch all descriptions
- Fixed critical *bad decrypt* issue blocking the user in a forever unable to sync state
- Fixed the links not being redirected on mobile

## Known issues

- On linux, graphs *can* have aliasing. It is a known issue of flutter dependencies, and I cannot fix it myself.