inherit package

AUTO_DEPEND_TYPES ?= ""
AUTO_DEPEND_TYPES[type] = "list"

AUTO_DEPEND_CLASSES = "${@' '.join('package-auto-deps/' + t for t in '${AUTO_DEPEND_TYPES}'.split())}"

inherit ${AUTO_DEPEND_CLASSES}


AUTO_MAPPED_DEPENDS_FILE = "{pkgdest}/{pkg}.{auto_type}.autodeps"
AUTO_DEPENDS_FILE = "{pkgdest}/auto/{auto_type}/{pkg}"


def auto_depend_included_types(d):
    return d.getVar('AUTO_DEPEND_TYPES', True).split()

def all_pkgdata_dirs(d):
    dirs = []
    triplets = (d.getVar("PKGTRIPLETS") or "").split()
    for t in triplets:
        dirs.append("${TMPDIR}/pkgdata/" + t)
    return " ".join(dirs)
all_pkgdata_dirs[vardepsexclude] = "PKGTRIPLETS"

PKGDATADIRS = "${@all_pkgdata_dirs(d)}"
PKGDATADIRS[type] = "list"

python process_automatic_dependencies() {
    """For each package, write out its automatic provides, and determine its
    automatic dependencies, for each defined automatic dependency type."""
    import collections

    packages = d.getVar('PACKAGES', True).split()
    pkgdestwork = d.getVar('PKGDESTWORK', True)
    context = bb.utils.get_context()

    for auto_type in auto_depend_included_types(d):
        auto_type_caps = auto_type.upper()
        hook = d.getVar("AUTO_DEPEND_{}_HOOK".format(auto_type_caps), True)
        if not hook:
            bb.fatal("AUTO_DEPEND_{}_HOOK is undefined".format(auto_type_caps))

        try:
            auto_provide_func_name, auto_depend_func_name = hook.split(None, 1)
        except ValueError:
            bb.fatal("Invalid value `{}` for AUTO_DEPEND_{}_HOOK".format(hook, auto_type_caps))

        if auto_provide_func_name not in context:
            bb.fatal("Unable to run undefined auto package hook function `{}`".format(auto_provide_func_name))
        auto_provide_func = context[auto_provide_func_name]

        if auto_depend_func_name not in context:
            bb.fatal("Unable to run undefined auto package hook function `{}`".format(auto_depend_func_name))
        auto_depend_func = context[auto_depend_func_name]

        destdir = os.path.join(pkgdestwork, 'auto', auto_type)
        bb.utils.mkdirhier(destdir)

        extra_depends, exclude_depends = get_manual_depends_data(auto_type, d)
        extra_provides, exclude_provides = get_manual_provides_data(auto_type, d)
        auto_provides, auto_depends = collections.defaultdict(set), collections.defaultdict(set)
        provided_by = {}
        for pkg in packages:
            provides = auto_provide_func(d, pkg, pkgfiles[pkg]) or []
            provides.extend(extra_provides.get(pkg, []))
            excluded_pkg_provides = exclude_provides.get(pkg)
            if excluded_pkg_provides:
                provides = filter(lambda p: p not in excluded_pkg_provides)

            if provides:
                bb.debug(1, "package_auto_deps: auto_provides %s for %s: %s" % (auto_type, pkg, provides))
                auto_provides[pkg] |= set(provides)

                for provide in provides:
                    provided_by[provide] = pkg
                    with open(os.path.join(destdir, provide), 'w') as f:
                        f.write(pkg)

            depends = auto_depend_func(d, pkg, pkgfiles[pkg]) or []
            depends.extend(extra_depends.get(pkg, []))
            excluded_pkg_depends = exclude_depends.get(pkg)
            if excluded_pkg_depends:
                depends = filter(lambda p: p not in excluded_pkg_depends)

            if depends:
                bb.debug(1, "package_auto_deps: auto_depends %s for %s: %s" % (auto_type, pkg, depends))
                auto_depends[pkg] |= set(d for d in depends if d not in auto_provides[pkg])


        pkgdata_dirs = oe.data.typed_value('PKGDATADIRS', d)

        def map_dependency(depend):
            if depend in provided_by:
                return provided_by[depend]

            for path in pkgdata_dirs:
                path = os.path.join(path, 'auto', auto_type)
                file_path = os.path.join(path, depend)
                if os.path.exists(file_path):
                    with open(file_path, 'r') as f:
                        dep_package = f.read().rstrip()
                        return dep_package

        for pkg in packages:
            mapped_depends = set()
            for depend in auto_depends[pkg]:
                split = depend.split()
                if len(split) == 1:
                    dep_package = map_dependency(depend)
                    if not dep_package:
                        bb.fatal("No available provider for dependency `{}` of {}".format(depend, pkg))
                else:
                    for i, word in enumerate(split):
                        if word in ("&", "|"):
                            continue
                        mapped = map_dependency(word) or word
                        split[i] = mapped
                    dep_package = ' '.join(split)
                mapped_depends.add(dep_package)
                provided_by[depend] = dep_package

            if mapped_depends:
                depsfile = d.expand("${PKGDEST}/" + pkg + '.' + auto_type + '.autodeps')
                with open(depsfile, 'w') as f:
                    f.writelines(d + '\n' for d in mapped_depends)
}

def get_manual_depends_data(auto_type, d):
    import collections

    auto_type_caps = auto_type.upper()
    extra_str = d.getVar('AUTO_{}_DEPENDS_EXTRA'.format(auto_type_caps), True) or ''
    extra = collections.defaultdict(set)
    for e in extra_str.split():
        pkg, depend = e.split(':', 1)
        extra[pkg].add(depend)

    exclude_str = d.getVar('AUTO_{}_DEPENDS_EXCLUDE'.format(auto_type_caps), True) or ''
    exclude = collections.defaultdict(set)
    for e in exclude_str.split():
        pkg, depend = e.split(':', 1)
        exclude[pkg].add(depend)

    return extra, exclude

def get_manual_provides_data(auto_type, d):
    import collections

    auto_type_caps = auto_type.upper()
    extra_str = d.getVar('AUTO_{}_PROVIDES_EXTRA'.format(auto_type_caps), True) or ''
    extra = collections.defaultdict(set)
    for e in extra_str.split():
        pkg, depend = e.split(':', 1)
        extra[pkg].add(depend)

    exclude_str = d.getVar('AUTO_{}_PROVIDES_EXCLUDE'.format(auto_type_caps), True) or ''
    exclude = collections.defaultdict(set)
    for e in exclude_str.split():
        pkg, depend = e.split(':', 1)
        exclude[pkg].add(depend)

    return extra, exclude

def auto_depend_vardeps(d):
    """Return variable dependencies for process_automatic_dependencies."""
    auto_package_types = auto_depend_included_types(d)
    vardeps = ['AUTO_DEPEND_TYPES']
    for t in auto_package_types:
        t_caps = t.upper()
        hook = 'AUTO_DEPEND_{}_HOOK'.format(t_caps)
        vardeps.append(hook)
        vardeps.extend((d.getVar(hook, True) or '').split())
        for e in ["EXTRA", "EXCLUDE"]:
            for m in ["DEPENDS", "PROVIDES"]:
                vardeps.append('AUTO_{}_{}_{}'.format(t_caps, m, e))
    return ' '.join(vardeps)

process_automatic_dependencies[vardeps] += "${@auto_depend_vardeps(d)}"

def read_autodep_files(d):
    """Read dep information written by process_automatic_dependencies"""
    import collections

    autodeps = {}
    packages = d.getVar('PACKAGES', True).split()
    for pkg in packages:
        autodeps[pkg] = collections.defaultdict(list)
        for auto_type in oe.data.typed_value('AUTO_DEPEND_TYPES', d):
            depsfile = d.expand("${PKGDEST}/" + pkg + '.' + auto_type + '.autodeps')
            if os.access(depsfile, os.R_OK):
                with open(depsfile, 'r') as f:
                    lines = f.readlines()

                for l in lines:
                    deps = bb.utils.explode_dep_versions2(l.rstrip())
                    for dep in deps:
                        if not dep in autodeps[pkg]:
                            autodeps[pkg][dep].extend(deps[dep])
    return autodeps

python read_autodeps () {
    """Read the autodep files written by process_automatic_dependencies, and
    update RDEPENDS with this information."""
    autodeps = read_autodep_files(d)

    packages = d.getVar('PACKAGES', True).split()
    for pkg in packages:
        rdepends = bb.utils.explode_dep_versions2(d.getVar('RDEPENDS_' + pkg, True) or "")
        for dep in autodeps[pkg]:
            # Add the dep if it's not already there, or if no comparison is set
            if dep not in rdepends:
                rdepends[dep] = []
            for v in autodeps[pkg][dep]:
                if v not in rdepends[dep]:
                    rdepends[dep].append(v)
        d.setVar('RDEPENDS_' + pkg, bb.utils.join_deps(rdepends, commasep=False))
}

PACKAGEFUNCS := "${@PACKAGEFUNCS.replace('read_shlibdeps', 'process_automatic_dependencies read_autodeps read_shlibdeps')}"
