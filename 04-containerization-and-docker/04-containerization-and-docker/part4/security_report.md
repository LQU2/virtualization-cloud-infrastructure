Container Security Analysis

A vulnerability scan was performed on the Docker images using a tool such as Trivy. The initial scan identified several critical in the base image. The single stage image contained critical vulnerabilities related to system libraries such as OpenSSL and BusyBox. High vulnerabilities were also found in Python dependencies and musl libc.

To reduce vulnerabilities, the following actions were taken:

- Switched to a multi stage build to reduce unnecessary packages
- Used a minimal base image (Alpine Linux)
- Removed unused dependencies

After applying improvements, the number of vulnerabilities decreased significantly. Only a small number of low and medium issues remained.

Using multistage build improves container security by reducing the attack surface.
