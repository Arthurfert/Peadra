# Installation

## Prerequisites
- Python 3.10 or higher
- pip (Python package manager)

## Setup

1. Clone the repository: (if you don't have git, download the zip file)
```bash
git clone https://github.com/Arthurfert/Peadra.git
cd Peadra
```

2. Create a virtual environment (*recommended*):
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt # Or requirements-dev.txt for pytests and linting
```

4. Run the application:
```bash
python main.py
```

> [!WARNING]
> For Ubuntu users, you might need to install the following dependencies:
> ```bash
> sudo apt install libmpv1
> ```
> If it doesn't work, try fixing it with this [stack overflow post](https://stackoverflow.com/questions/78007193/error-while-loading-shared-libraries-libmpv-so-1-cannot-open-shared-object-fil).

> [!TIP]
> Use the Makefile to make all this easier ! (run `make help` for all available commands)

# Package

**You need to download the project before.**

To package the app in one executable file (all OS) : 
``` bash
make pack
```

# Build (with entire dependencies files)

**You need to download the project before.**

## Windows

Prerequisites : 
- Visual Studio with *Desktop Development in C/C++* workload installed
- On windows, you will need developers mode enabled

```bash
flet build windows
```

## Linux

```bash
flet build linux
```

## MacOS

Prerequisites : 
- Rosetta 2 *on Apple Silicon* (for packaging)
- Xcode (compile swift or objective-C code)
- CocoaPods (install and compile flutter plugins)

```bash
flet build macos
```