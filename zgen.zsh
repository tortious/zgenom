#!/bin/zsh
local ZGEN_SOURCE="$(cd "$(dirname "${0}")" && pwd -P)"


if [[ -z "${ZGEN_DIR}" ]]; then
    ZGEN_DIR="${HOME}/.zgen"
fi

if [[ -z "${ZGEN_INIT}" ]]; then
    ZGEN_INIT="${ZGEN_DIR}/init.zsh"
fi

if [[ -z "${ZGEN_LOADED}" ]]; then
    ZGEN_LOADED=()
fi

if [[ -z "${ZGEN_COMPLETIONS}" ]]; then
    ZGEN_COMPLETIONS=()
fi

-zgen-get-clone-dir() {
    local repo="${1}"
    local branch="${2:-master}"

    if [[ -d "${repo}/.git" ]]; then
        echo "${ZGEN_DIR}/local/$(basename ${repo})-${branch}"
    else
        echo "${ZGEN_DIR}/${repo}-${branch}"
    fi
}

-zgen-get-clone-url() {
    local repo="${1}"

    if [[ -d "${repo}/.git" ]]; then
        echo "${repo}"
    else
        # Sourced from antigen url resolution logic.
        # https://github.com/zsh-users/antigen/blob/master/antigen.zsh
        # Expand short github url syntax: `username/reponame`.
        if [[ $repo != git://* &&
              $repo != https://* &&
              $repo != http://* &&
              $repo != ssh://* &&
              $repo != git@github.com:*/*
              ]]; then
            repo="https://github.com/${repo%.git}.git"
        fi
        echo "${repo}"
    fi
}

zgen-clone() {
    local repo="${1}"
    local branch="${2:-master}"
    local url="$(-zgen-get-clone-url ${repo})"
    local dir="$(-zgen-get-clone-dir ${repo} ${branch})"

    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
        git clone --recursive -b "${branch}" "${url}" "${dir}"
    fi
}

-zgen-add-to-fpath() {
    local completion_path="${1}"

    # Add the directory to ZGEN_COMPLETIONS array if not present
    if [[ ! "${ZGEN_COMPLETIONS[@]}" =~ ${completion_path} ]]; then
        ZGEN_COMPLETIONS+=("${completion_path}")
    fi
}

-zgen-source() {
    local file="${1}"

    source "${file}"

    # Add to ZGEN_LOADED array if not present
    if [[ ! "${ZGEN_LOADED[@]}" =~ "${file}" ]]; then
        ZGEN_LOADED+=("${file}")
    fi

    completion_path="$(dirname ${file})"

    -zgen-add-to-fpath "${completion_path}"
}

zgen-init() {
    if [[ -f "${ZGEN_INIT}" ]]; then
        source "${ZGEN_INIT}"
    fi
}

zgen-reset() {
    echo "zgen: Deleting ${ZGEN_INIT}"
    if [[ -f "${ZGEN_INIT}" ]]; then
        rm "${ZGEN_INIT}"
    fi
}

zgen-update() {
    for repo in "${ZGEN_DIR}"/*/*; do
        echo "Updating ${repo}"
        (cd "${repo}" \
            && git pull \
            && git submodule update --recursive)
    done
    zgen-reset
}

zgen-save() {
    echo "zgen: Creating ${ZGEN_INIT}"

    echo "#" >! "${ZGEN_INIT}"
    echo "# Generated by zgen." >> "${ZGEN_INIT}"
    echo "# This file will be overwritten the next time you run zgen save" >> "${ZGEN_INIT}"
    echo "#" >> "${ZGEN_INIT}"
    for file in "${ZGEN_LOADED[@]}"; do
        echo "source \"${(q)file}\"" >> "${ZGEN_INIT}"
    done

    # Set up fpath
    echo >> "${ZGEN_INIT}"
    echo "#" >> "${ZGEN_INIT}"
    echo "# Add our plugins and completions to fpath">> "${ZGEN_INIT}"
    echo "#" >> "${ZGEN_INIT}"
    echo "fpath=(${(q)ZGEN_COMPLETIONS[@]} \${fpath})" >> "${ZGEN_INIT}"

    echo "zgen: Creating ${ZGEN_DIR}/zcompdump"
    compinit -d "${ZGEN_DIR}/zcompdump"
}

zgen-completions() {
    echo "zgen: 'completions' is deprecated, please use 'load' instead"

    zgen-load "${@}"
}

zgen-load() {
    local repo="${1}"
    local file="${2}"
    local branch="${3:-master}"
    local dir="$(-zgen-get-clone-dir ${repo} ${branch})"
    local location="${dir}/${file}"

    # clone repo if not present
    if [[ ! -d "${dir}" ]]; then
        zgen-clone "${repo}" "${branch}"
    fi

    # source the file
    if [[ -f "${location}" ]]; then
        -zgen-source "${location}"

    # Prezto modules have init.zsh files
    elif [[ -f "${location}/init.zsh" ]]; then
        -zgen-source "${location}/init.zsh"

    elif [[ -f "${location}.zsh-theme" ]]; then
        -zgen-source "${location}.zsh-theme"

    elif [[ -f "${location}.theme.zsh" ]]; then
        -zgen-source "${location}.theme.zsh"

    elif [[ -f "${location}.zshplugin" ]]; then
        -zgen-source "${location}.zshplugin"

    elif [[ -f "${location}.zsh.plugin" ]]; then
        -zgen-source "${location}.zsh.plugin"

    # Classic oh-my-zsh plugins have foo.plugin.zsh
    elif ls "${location}" | grep -l "\.plugin\.zsh" &> /dev/null; then
        for script (${location}/*\.plugin\.zsh(N)) -zgen-source "${script}"

    elif ls "${location}" | grep -l "\.zsh" &> /dev/null; then
        for script (${location}/*\.zsh(N)) -zgen-source "${script}"

    elif ls "${location}" | grep -l "\.sh" &> /dev/null; then
        for script (${location}/*\.sh(N)) -zgen-source "${script}"

    # Completions
    elif [[ -d "${location}" ]]; then
        -zgen-add-to-fpath "${location}"

    else
        echo "zgen: Failed to load ${dir}"
    fi
}

zgen-saved() {
    [[ -f "${ZGEN_INIT}" ]] && return 0 || return 1
}

zgen-list() {
    if [[ -f "${ZGEN_INIT}" ]]; then
        cat "${ZGEN_INIT}"
    else
        echo "Zgen init.zsh missing, please use zgen save and then restart your shell."
    fi
}

zgen-selfupdate() {
    if [[ -e "${ZGEN_SOURCE}/.git" ]]; then
        (cd "${ZGEN_SOURCE}" \
            && git pull)
    else
        echo "zgen is not running from a git repository, so it is not possible to selfupdate"
        return 1
    fi
}

zgen-oh-my-zsh() {
    local repo="robbyrussell/oh-my-zsh"
    local file="${1:-oh-my-zsh.sh}"

    zgen-load "${repo}" "${file}"
}

zgen() {
    local cmd="${1}"
    if [[ -z "${cmd}" ]]; then
        echo "usage: zgen [clone|completions|list|load|oh-my-zsh|reset|save|selfupdate|update]"
        return 1
    fi

    shift

    if functions "zgen-${cmd}" > /dev/null ; then
        "zgen-${cmd}" "${@}"
    else
        echo "zgen: command not found: ${cmd}"
    fi
}

ZSH="$(-zgen-get-clone-dir robbyrussell/oh-my-zsh master)"
zgen-init
fpath=($ZGEN_SOURCE $fpath)

autoload -U compinit
compinit -d "${ZGEN_DIR}/zcompdump"
