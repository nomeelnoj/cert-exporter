#
# requires a k8s cluster running with cert-manager running in it
#  assumes the location of kubeconfig at ~/.kube/config
# requires k3d
#

validateMetrics() {
    metrics=$1
    expectedVal=$2    

    raw=$(curl --silent http://localhost:8080/metrics | grep "$metrics")

    if [ "$raw" == "" ]; then
      echo "TEST FAILURE: $metrics" 
      echo "  Unable to find metrics string"
      return 0
    fi

    val=${raw#* }
    valInDays=$(awk "BEGIN {printf \"%.0f\", $val / (24 * 60 * 60)}")

    if [ "$expectedVal" -ne "$valInDays" ]; then
      echo "TEST FAILURE: $metrics"
      echo "  Expected  : $expectedVal"
      echo "  Raw       : $raw"
      echo "  Val       : $val"
      echo "  ValInDays : $valInDays"
    else 
      echo "TEST SUCCESS: $metrics"
    fi
}

export KUBECONFIG=""
K3D_NAME=cert-exporter
CONFIG_PATH="k3d get-kubeconfig --name=$K3D_NAME"

k3d create --name=$K3D_NAME
echo -n "Ensuring k3d is running..."
while true; do
  k3d list 2>&1 | grep ".*$K3D_NAME.*running" >/dev/null && echo "done" && break \
    || (echo -n . && sleep 1)
done

echo -n "Getting kubeconfig..."
while true; do
  eval $CONFIG_PATH 2>&1 | grep "$K3D_NAME/kubeconfig.yaml" >/dev/null && echo done && break \
    || (echo -n . && sleep 1)
done
echo Config is available at $(eval $CONFIG_PATH)

kubectl --kubeconfig $(eval $CONFIG_PATH) create namespace cert-manager
kubectl --kubeconfig $(eval $CONFIG_PATH) label namespace cert-manager certmanager.k8s.io/disable-validation=true
kubectl --kubeconfig $(eval $CONFIG_PATH) apply -f https://github.com/jetstack/cert-manager/releases/download/v0.10.1/cert-manager.yaml

sleep 90

kubectl --kubeconfig $(eval $CONFIG_PATH) create -f ./certs.yaml

echo "** Testing Label Selector"
# run exporter
go build ../../main.go
chmod +x ./main

go run ../../main.go --kubeconfig $(eval $CONFIG_PATH) \
               --secrets-label-selector 'certmanager.k8s.io/certificate-name' \
               --alsologtostderr &
pid=$!
sleep 5

validateMetrics 'cert_exporter_secret_expires_in_seconds{key_name="ca.crt",secret_name="selfsigned-cert-tls",secret_namespace="cert-manager-test"}' 100

# kill exporter
kill $pid

echo "** Testing Label Selector And Namespace"
# run exporter
go run ../../main.go --kubeconfig $(eval $CONFIG_PATH) \
               --secrets-label-selector 'certmanager.k8s.io/certificate-name' \
               --secrets-namespace 'cert-manager-test' \
               --alsologtostderr &
pid=$!
sleep 5

validateMetrics 'cert_exporter_secret_expires_in_seconds{key_name="ca.crt",secret_name="selfsigned-cert-tls",secret_namespace="cert-manager-test"}' 100

# kill exporter
kill $pid

read -p "press enter"

rm ./main
kubectl --kubeconfig $(eval $CONFIG_PATH) delete -f ./certs.yaml
k3d delete --name=$K3D_NAME