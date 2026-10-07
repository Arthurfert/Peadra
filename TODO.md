# TODO

**The application is not intended to become cloud-based, and will stay local.**

> [!NOTE]
> An API access to your bank either need a approval from an organization, or isn't free (services like Plaid). It is thus not possible.

## Currently in development

### New

- **Budget view :**
  - Set your goals for any account, expense or revenue category, or even your entire patrimony
  - Choose monthly goals, or your specific period of time
  - View how far you are from your goal
- **Spanish** support !
- Custom time period selection in the dashboard

### Fixes

- Fixed bug where some transactions displayed '-' instead of the description (bad decrypt)
- Tags are now the default setting for graphs

## Known issues

- On linux only, graphs *can sometimes* have aliasing. It is a known issue of flutter dependencies with some graphical drivers.