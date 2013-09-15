## Automatic python and python module dependencies

# Usage examples for per-type extra/exclude variables for the 'python' type
#AUTO_PYTHON_DEPENDS_EXTRA += "python-foo:os.path"
#AUTO_PYTHON_DEPENDS_EXCLUDE += "python-foo:urllib.parse"
#AUTO_PYTHON_PROVIDES_EXTRA += "python-core:os.path"
#AUTO_PYTHON_PROVIDES_EXCLUDE += "python-core:sys"


# Which module implements os.path varies with OS
AUTO_PYTHON_PROVIDES_EXTRA += "python-core:os.path"

AUTO_DEPEND_PYTHON_HOOK = "determine_python_provides determine_python_depends"

PYTHON_DEPS_SEARCH_PATHS = "${PYTHON_SITEPACKAGES_DIR}"
PYTHON_DEPS_SEARCH_PATHS[type] = "list"

PYTHON_PROVIDES_SEARCH_PATHS = "${PYTHON_SITEPACKAGES_DIR} ${libdir}/python${PYTHON_MAJMIN}"
PYTHON_PROVIDES_SEARCH_PATHS[type] = "list"

PYTHON_EXECUTABLE_SEARCH_PATHS = "${bindir} ${base_bindir} ${sbindir} ${libexecdir}"
PYTHON_EXECUTABLE_SEARCH_PATHS[type] = "list"

PYTHON_INTERPRETER_PATTERN = "python([0-9].[0-9])$"
PYTHON_INTERPRETER_PATTERN[type] = "regex"

PYTHON_SHEBANG_PREFIXES = "${bindir}/env |${bindir}/"
PYTHON_SHEBANG_PREFIXES[type] = "list"
PYTHON_SHEBANG_PREFIXES[separator] = "|"

PYTHONDEPS_FILE = "${@bb.utils.which(BBPATH, 'scripts/pythondeps')}"
PYTHONDEPS_FILE_CHECKSUM = "${@bb.utils.md5_file(PYTHONDEPS_FILE)}"
PYTHONDEPS_FILE_CHECKSUM[vardepvalue] = "${PYTHONDEPS_FILE_CHECKSUM}"
PYTHONDEPS_FILE_CHECKSUM[vardepsexclude] += "PYTHONDEPS_FILE"

# Lxml supports both python 2 and 3, so has many imports in try/except blocks
# to handle module renames, and pythondeps isn't smart enough to handle that
# just yet
PYTHON_DEPS_SEARCH_PATHS_pn-python-lxml = ""

def determine_python_provides(d, pkg, files):
    import subprocess

    pkgdest = d.getVar('PKGDEST', True)
    inst_root = os.path.join(pkgdest, pkg)
    depscmd = d.getVar('PYTHONDEPS_FILE', True)
    provides = []

    search_paths = oe.data.typed_value('PYTHON_PROVIDES_SEARCH_PATHS', d)
    dest_paths = filter(os.path.exists,
                        [oe.path.join(inst_root, path) for path in search_paths])
    if dest_paths:
        output = subprocess.check_output([depscmd, '-p'] + dest_paths)
        provides.extend(l.rstrip() for l in output.splitlines())

    bindir = oe.path.join(inst_root, d.getVar('bindir', True))
    if os.path.isdir(bindir):
        for exe in os.listdir(bindir):
            pattern = oe.data.typed_value('PYTHON_INTERPRETER_PATTERN', d)
            m = pattern.match(exe)
            if m:
                provides.append('python' + m.group(1))

    return provides

determine_python_provides[vardeps] += "PYTHONDEPS_FILE_CHECKSUM"

def determine_python_depends(d, pkg, files):
    import re
    import subprocess

    pkgdest = d.getVar('PKGDEST', True)
    inst_root = os.path.join(pkgdest, pkg)
    depscmd = d.getVar('PYTHONDEPS_FILE', True)
    depends = []

    search_paths = oe.data.typed_value('PYTHON_DEPS_SEARCH_PATHS', d)
    dest_paths = filter(os.path.exists,
                        [oe.path.join(inst_root, path) for path in search_paths])
    if dest_paths:
        output = subprocess.check_output([depscmd, '-d'] + dest_paths)
        depends.extend(l.rstrip() for l in output.splitlines())

    interpreter_pattern = d.getVar('PYTHON_INTERPRETER_PATTERN', True)
    prefix_patterns = []
    for prefix in oe.data.typed_value('PYTHON_SHEBANG_PREFIXES', d):
        prefix_patterns.append(re.compile('#!' + prefix + interpreter_pattern))

    for bindir in oe.data.typed_value('PYTHON_EXECUTABLE_SEARCH_PATHS', d):
        dest_bindir = oe.path.join(inst_root, bindir)
        if os.path.exists(dest_bindir):
            scripts = []
            for exe in os.listdir(dest_bindir):
                dest_exe = os.path.join(dest_bindir, exe)
                if not os.path.isfile(dest_exe):
                    continue

                with open(dest_exe, 'r') as f:
                    first_line = f.readline().rstrip()
                    for pattern in prefix_patterns:
                        m = pattern.match(first_line)
                        if m:
                            dep_version = m.group(1)
                            if dep_version:
                                depends.append('python' + dep_version)
                            scripts.append(dest_exe)
                            break

            if scripts:
                output = subprocess.check_output([depscmd, '-d'] + scripts)
                depends.extend(l.rstrip().split(None, 1)[0] for l in output.splitlines())

    return depends

determine_python_depends[vardeps] += "PYTHONDEPS_FILE_CHECKSUM"
