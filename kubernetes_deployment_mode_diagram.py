from diagrams import Cluster, Diagram
from diagrams.k8s.compute import Deploy, DaemonSet, Pod
from diagrams.k8s.podconfig import ConfigMap

with Diagram("kubernetes.deployment.enabled", show=True, direction="LR"):
    ds = None
    deploy = None
    with Cluster("Namespace\nvcagent"):
        with Cluster("Deployment\nkubernetes-sensor"):
            deploy = Pod("2 Replicas\nKubernetes Sensor")

        with Cluster("DaemonSet\nvcagent"):
            ds = Pod('Per Node\nHost & APM')

        cm = ConfigMap("vcagent")
        dcm = ConfigMap("vcagent-deployment")

        cm >> deploy
        cm >> ds
        dcm >> deploy