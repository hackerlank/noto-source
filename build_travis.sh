# Copyright 2016 Google Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source util.sh

function main() {
    branch="${TRAVIS_BRANCH}"
    event="${TRAVIS_EVENT_TYPE}"
    commit_range="${TRAVIS_COMMIT_RANGE}"

    # do nothing unless pushing to staging or master
    if [[ ( "${branch}" != 'master' && "${branch}" != 'staging' ) ||
          "${event}" != 'push' ]]; then
        exit 0
    fi

    outdir='instance_ttf'
    cached_outdir='output'

    #TODO use a separate report path, directory and branch for each change, to
    # allow for simultaneous reviews. would have to clean them up afterwards.
    cmp_dir='comparisons'
    cmp_report="${cmp_dir}/report.txt"
    cache_branch='gh-pages'

    # build the updated sources
    echo "building sources changed from ${commit_range}"
    git diff --name-only "${commit_range}" | while read src; do
        if [[ "${src}" =~ src/[^/]+\.glyphs ]]; then
            build_glyphs "${src}" 'ttf'
        elif [[ "${src}" =~ src/[^/]+/[^/]+\.plist ]]; then
            build_plist "${src}" 'ttf'
        elif [[ "${src}" =~ src/[^/]+/[^/]+\.glyphs ]]; then
            for plist_src in $(dirname "${src}")/*.plist; do
                build_plist "${plist_src}" 'ttf'
            done
        fi
    done
    if [[ -e "${outdir}" ]]; then
        echo 'new output:'
        ls "${outdir}"
    else
        echo 'no sources changed'
        exit 0
    fi

    # switch to cache branch and make sure there's a directory for cached fonts
    git remote set-branches --add origin "${cache_branch}"
    git fetch
    git checkout "${cache_branch}"
    if [[ ! -d "${cached_outdir}" ]]; then
        mkdir "${cached_outdir}"
    fi

    # configure git for bot account
    git config 'user.name' 'noto-buildbot'
    git config 'user.email' 'noto-buildbot@google.com'
    git_url='github.com/googlei18n/noto-source'
    credentials="noto-buildbot:${noto_buildbot_token}"

    # just cache new output if pushed to master
    if [[ "${branch}" == 'master' ]]; then
        for ttf in ${outdir}/*.ttf; do
            mv "${ttf}" "${cached_outdir}"
        done
        git add "${cached_outdir}"
        git commit -m 'Update cached output' --amend
        git push --force "https://${credentials}@${git_url}.git"\
            "${cache_branch}" >/dev/null 2>&1
        exit 0
    fi

    # otherwise, compare new output with old
    #TODO add more tests and comparisons (fontreport, notolint, unit tests)
    git rm -r "${cmp_dir}"
    mkdir "${cmp_dir}"

    echo 'running notodiff rendering check...'
    notodiff -t 'rendered' --render-path "${cmp_dir}" --diff-threshold 0.01\
        -m '*.ttf' --before "${cached_outdir}" --after "${outdir}"\
        --verbose 'INFO' >> "${cmp_report}"

    echo 'running fontdiff...'
    for ttf in ${outdir}/*.ttf; do
        ttf_basename="$(basename "${ttf}")"
        cached_ttf="${cached_outdir}/${ttf_basename}"
        if [[ ! -e "${cached_ttf}" ]]; then
            echo "Cached font not found for ${ttf}"
            continue
        fi

        #TODO add comprehensive text samples to noto-source and use those here
        echo "checking ${ttf} against ${cached_ttf}"
        specimen="$(python generate_fontdiff_input.py\
                    "${ttf}" 'nototools/sample_texts')"
        if [[ "${specimen}" == 'None' ]]; then
            echo 'no input text found'
            continue
        fi
        out_pdf="${ttf_basename/%.ttf/.pdf}"
        ./fontdiff --before "${cached_ttf}" --after "${ttf}"\
            --specimen "${specimen}" --out "${out_pdf}"
        exit_status="$?"
        msg="fontdiff exit status for ${ttf}: ${exit_status}"
        echo "${msg}"
        if [[ "${exit_status}" -ne 0 ]]; then
            echo "${msg}" >> "${cmp_report}"
            mv "${out_pdf}" "${cmp_dir}"
        fi
    done

    # check that some comparisons were made
    if [[ ! $(ls "${cmp_dir}"/*/*.png "${cmp_dir}"/*.pdf) ]]; then
        echo 'No comparisons made for these changes'
        exit 1
    fi

    # generate comparison summary and upload
    python generate_html.py "${commit_range}" "${cmp_dir}"
    git add 'index.html' "${cmp_dir}"
    git commit -m 'Review commit' --amend
    git push --force "https://${credentials}@${git_url}.git"\
        "${cache_branch}" >/dev/null 2>&1

    # create a new pull request to master
    pull_request_json='{
        "title": "Review request",
        "body": "Review report of changes at
            https://googlei18n.github.io/noto-source/.",
        "head": "staging",
        "base": "master"
    }'
    #curl -u "${credentials}" -d "${pull_request_json//$'\n'/}"\
    #    'https://api.github.com/repos/googlei18n/noto-source/pulls'
    #TODO find and post a comment on the original PR to staging
}

main "$@"
