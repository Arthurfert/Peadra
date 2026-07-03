
# Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Workflow

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally and navigate into the project:
```bash
git clone https://github.com/Arthurfert/Peadra.git
cd Peadra
```

3. **Checkout the `dev` branch** and make sure it is up to date:
```bash
git checkout dev
git pull origin dev
```


4. **Create your feature branch** off of `dev`:
```bash
git checkout -b feature/your-feature-name
```


5. **Make your changes** and commit them:
```bash
git add .
git commit -m "Description of the changes made"
```


6. **Push your branch** to your GitHub fork:
```bash
git push origin feature/your-feature-name
```


7. **Open a Pull Request** on GitHub, making sure to target the base branch as `dev`.

---

> [!IMPORTANT]
> **Branching Rule:** Always branch out from `dev`. The `main` branch is reserved strictly for automatic building, testing, and production releases via our CI/CD pipeline.

> [!NOTE]
> If you want to report a bug or suggest an idea, please open an Issue on GitHub (unless you have already fixed it in your PR!).
