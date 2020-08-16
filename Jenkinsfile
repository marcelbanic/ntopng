pipeline {
    agent any
    environment{
        DOCKER_TAG = getDockerTag()
    }
    stages{
        stage('Build Docker Image'){
            steps{
                sh "docker build . -t marcelbanic/ntopng:${DOCKER_TAG} "
            }
        }
        stage('DockerHub Push'){
            steps{
                withCredentials([string(credentialsId: 'docker-hub', variable: 'dockerHubPwd')]) {
                    sh "docker login -u marcelbanic -p ${dockerHubPwd}"
                    sh "docker push marcelbanic/ntopng:${DOCKER_TAG}"
                }
            }
        }
        stage('Deploy to Dev server'){
            steps{
                ansiblePlaybook extras: "-e tag=${env.DOCKER_TAG}", 
                                credentialsId: 'slave-one', 
                                playbook: 'ansible/docker-deploy.yml'
            }
        }
    }
}

def getDockerTag(){
    def tag  = sh script: 'git rev-parse HEAD', returnStdout: true
    return tag
}