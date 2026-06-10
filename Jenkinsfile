// SPDX-License-Identifier: Apache-2.0
//
// Jenkinsfile - declarative pipeline mirroring .gitlab-ci.yml.
//
// Every stage's body is a single `sh './scripts/<verb>.sh'` call. Logic
// lives in scripts/, not Groovy. Switching CI platforms is a half-day
// port of the dispatch files; the scripts do not change.

pipeline {
    agent {
        docker {
            image 'ubuntu:22.04'
            args  '-u 0:0'
        }
    }

    environment {
        DEBIAN_FRONTEND = 'noninteractive'
        CMAKE_FLAGS     = '-DMOCKACCEL_BUILD_PYTHON=OFF'
        SHFMT_VERSION   = 'v3.8.0'
	HADOLINT_VERSION = 'v2.12.0'
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        ansiColor('xterm')
    }

    stages {
        // Install every tool the pipeline needs once, up front. GitLab's
        // .install-shell-tools / .install-build-tools split is idiomatic
        // there; in Jenkins's one-agent-per-pipeline model a single
        // Prepare stage is the equivalent native idiom.
        stage('Prepare') {
            steps {
                sh '''
                    apt-get update -qq
                    apt-get install -y --no-install-recommends \
                        shellcheck curl ca-certificates git \
                        build-essential cmake ninja-build \
                        g++-aarch64-linux-gnu qemu-user-static file
                    curl -fsSL -o /usr/local/bin/shfmt \
                        "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
                    curl -fsSL -o /usr/local/bin/hadolint \
			"https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64"
		    chmod +x /usr/local/bin/shfmt
		    chmod +x /usr/local/bin/hadolint
                    shellcheck --version
                    shfmt --version
		    hadolint --version
                    cmake --version
                    ninja --version
                    aarch64-linux-gnu-g++ --version
                    qemu-aarch64-static --version
                    file --version
                    git --version
                '''
            }
        }

        stage('Lint') {
            steps { sh './scripts/lint.sh' }
        }

        stage('Build') {
            steps { sh './scripts/build.sh' }
        }

        stage('Test') {
            steps { sh './scripts/test.sh' }
        }

        stage('Cross-build') {
            steps {
                sh '''
                    ./scripts/build.sh --target=aarch64
                    BIN=build-aarch64/device_simulator/mockaccel_device_simulator
                    file "${BIN}"
                    file "${BIN}" | grep -q "ELF 64-bit LSB.*ARM aarch64"
                    qemu-aarch64-static "${BIN}" --version
                '''
            }
        }

        stage('Package') {
            steps { sh './scripts/package.sh' }
        }

        // Publish runs on main and on v*.*.* tags - mirrors the GitLab
        // publish job's rules: block.
        stage('Publish') {
            when {
                anyOf {
                    branch 'main'
                    buildingTag()
                }
            }
            steps { sh './scripts/publish.sh' }
        }

        // Deploy and Release run only on v*.*.* tags.
        stage('Deploy') {
            when { tag pattern: 'v*.*.*', comparator: 'GLOB' }
            steps { sh './scripts/deploy.sh' }
        }

        stage('Release') {
            when { tag pattern: 'v*.*.*', comparator: 'GLOB' }
            steps {
                echo "Creating release for ${env.TAG_NAME}"
                // Stage 10 will replace this with git-cliff + gitlab-release.
            }
        }
    }

    post {
        always {
            echo "Pipeline finished: ${currentBuild.currentResult}"
        }
        failure {
            echo 'Pipeline failed. See stage logs above.'
        }
    }
}
