# Copyright 2015 Google Inc. All rights reserved.
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

setup() {
    if [[ ! $(python -m pip) ]]; then
        if [[ ! $(sudo python -m ensurepip) ]]; then
            echo 'You need to manually install pip.'
            exit 1
        fi
    fi
    pip install --user virtualenv
    python -m virtualenv env
    source env/bin/activate
    pip install --upgrade -r Lib/fontmake/requirements.txt
    cd Lib/fontmake
    pip install .
    deactivate
}

build_all() {
    for target in src/*.glyphs src/*/*.plist src/*/*.ufo; do
        echo "==== building ${target} ===="
        build_one "${target}" "$1"
        echo
    done
}

build_one() {
    source env/bin/activate
    case "$1" in
        *.plist)
            build_plist "$1" 'otf' 'ttf'
            ;;
        *.glyphs)
            build_glyphs "$1" 'otf' 'ttf'
            ;;
        *.ufo)
            build_ufo "$1"
            ;;
        *)
            echo "unrecognized file type $1"
            exit 1
            ;;
    esac
    if [[ "$?" -ne 0 && "$2" != 'force' ]]; then
        exit 1
    fi
    deactivate
}

main() {
    case "$1" in
        setup) setup ;;
        build_one) build_one "$2" ;;
        *) build_all "$1" ;;
    esac
}

main "$@"
