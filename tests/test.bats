setup() {
  set -eu -o pipefail
  export BATS_LIB_PATH="${BATS_LIB_PATH:-}:$(brew --prefix)/lib"
  bats_load_library bats-assert
  bats_load_library bats-support
  export DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )/.."
  export TESTDIR=~/tmp/test-ddev-opencode
  mkdir -p $TESTDIR
  export PROJNAME=test-ddev-opencode
  export DDEV_NON_INTERACTIVE=true
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  ddev config --project-name=${PROJNAME}
  ddev start -y >/dev/null
}

health_checks() {
  # Wait for OpenCode container to start
  sleep 10
  # Verify opencode container is running
  run ddev exec -s opencode opencode --version
  assert_success
  # Verify web container access
  run ddev exec -s opencode docker exec ddev-${PROJNAME}-web php -v
  assert_success
}

teardown() {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  ddev delete -Oy ${PROJNAME} >/dev/null 2>&1
  [ "${TESTDIR}" != "" ] && rm -rf ${TESTDIR}
}

@test "install from directory" {
  set -eu -o pipefail
  cd ${TESTDIR}
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in ${TESTDIR} ($(pwd))" >&3
  ddev add-on get ${DIR}
  ddev restart >/dev/null
  health_checks
}

@test "install from release" {
  set -eu -o pipefail
  cd ${TESTDIR} || ( printf "unable to cd to ${TESTDIR}\n" && exit 1 )
  echo "# ddev add-on get trebormc/ddev-opencode with project ${PROJNAME} in ${TESTDIR} ($(pwd))" >&3
  ddev add-on get trebormc/ddev-opencode
  ddev restart >/dev/null
  health_checks
}
