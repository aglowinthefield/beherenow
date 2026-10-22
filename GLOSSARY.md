# Glossary

- **Hide**: Be Here Now hides an application the way Command-H does. The application keeps running.
- **Delay**: how long an application stays out of focus before it hides. It starts when the application loses focus or appears in the background. Returning to the application clears it.
- **Default delay**: the delay for every application without its own rule. 60 seconds unless changed.
- **Custom delay**: a per-application delay that replaces the default delay.
- **Never hide**: a per-application rule that keeps the application visible, even in Zazen mode.
- **Zazen mode**: hides applications as soon as they lose focus, ignoring all delays.
- **Hide scheduler**: the module (`HideScheduler`) that tracks each application's delay from workspace events and reports which applications are due to hide.
