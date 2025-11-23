## 🛠️ SPIRE Server and Agent Installation on Ubuntu 22.04

This process covers the quickstart for both the server and agent on a single Linux machine, which is often used for demonstration or testing purposes.

-----

### 1\. Prerequisites and Binary Download

First, ensure you have a 64-bit Linux environment and the `openssl` command-line tool. You will need to download and unpack the SPIRE binaries.

1.  **Create an installation directory and navigate into it:**

    ```bash
    sudo mkdir -p /opt/spire
    cd /opt/spire
    ```

2.  **Download and extract the latest SPIRE tarball (check the [SPIFFE downloads page](https://spiffe.io/docs/latest/deploying/install-server/) for the current version to use in the `wget` command):**

    ```bash
    # Using v1.12.5 as an example - replace with the latest version
    SPIRE_VERSION="1.12.5"
    wget https://github.com/spiffe/spire/releases/download/v${SPIRE_VERSION}/spire-${SPIRE_VERSION}-linux-amd64-musl.tar.gz
    tar zvxf spire-${SPIRE_VERSION}-linux-amd64-musl.tar.gz
    sudo cp -r spire-${SPIRE_VERSION}/. /opt/spire/
    ```

3.  **Add the binaries to your $PATH for convenience:**

    ```bash
    sudo ln -s /opt/spire/bin/spire-server /usr/bin/spire-server
    sudo ln -s /opt/spire/bin/spire-agent /usr/bin/spire-agent
    ```

-----

### 2\. Configure and Run the SPIRE Server

The binaries package includes example configuration files. We'll use the default server configuration located at `/opt/spire/conf/server/server.conf`.

1.  **Start the SPIRE Server (run in the background):**
    ```bash
    /opt/spire/bin/spire-server run -config /opt/spire/conf/server/server.conf &
    ```
    (You may need to run this command from the `/opt/spire` directory if the configuration file paths are relative).

-----

### 3\. Configure and Run the SPIRE Agent

The SPIRE Agent needs to attest to the Server. The simplest attestation method for a quick setup is using a **join token**.

1.  **Generate a one-time-use join token from the Server:**

    ```bash
    TOKEN=$(/opt/spire/bin/spire-server token generate -spiffeID spiffe://example.org/myagent | grep Token | awk '{print $2}')
    echo "Generated Token: $TOKEN"
    ```

2.  **Start the SPIRE Agent using the join token (run in the background):**

    ```bash
    /opt/spire/bin/spire-agent run -config /opt/spire/conf/agent/agent.conf -joinToken $TOKEN &
    ```

3.  **Check the Agent's health:**

    ```bash
    /opt/spire/bin/spire-agent healthcheck
    ```

    It should output: `Agent is healthy.`

-----

### 4\. End-to-End Testing (Workload Registration and SVID Fetch)

To complete an end-to-end test, you must register a **workload** with the Server and then confirm the Agent can fetch the workload's **SVID** (SPIFFE Verifiable Identity Document). We'll use the `unix:uid` selector, which is the most convenient for a single-node test.

1.  **Create a registration entry for a workload:**
    This command registers an entry with the SPIFFE ID `spiffe://example.org/myservice` and ties it to the current user's UID (Workload Attestation).

    ```bash
    /opt/spire/bin/spire-server entry create \
    -parentID spiffe://example.org/myagent \
    -spiffeID spiffe://example.org/myservice \
    -selector unix:uid:$(id -u)
    ```

2.  **Fetch the SVID for the workload using the Agent's Workload API:**
    This command simulates your workload asking for its identity. Since we used the current user's UID for the selector, the Agent should issue the SVID.

    ```bash
    /opt/spire/bin/spire-agent api fetch x509
    ```

    If successful, you will see a list of SPIFFE IDs and the corresponding SVID details, confirming the full end-to-end identity flow is working.

