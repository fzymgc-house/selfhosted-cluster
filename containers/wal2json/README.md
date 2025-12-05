# wal2json Extension Image

Container image for the [wal2json](https://github.com/eulerto/wal2json) PostgreSQL logical decoding output plugin, built for use with CloudNativePG's ImageVolume feature.

## Usage

This image is designed for CNPG's ImageVolume extension loading (requires Kubernetes 1.33+ and PostgreSQL 18+).

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-postgres
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie

  postgresql:
    parameters:
      wal_level: logical
    extensions:
      - name: wal2json
        image:
          reference: ghcr.io/fzymgc-house/wal2json:2.6-pg18-trixie
```

## Image Details

| Property | Value |
|----------|-------|
| Registry | `ghcr.io/fzymgc-house/wal2json` |
| Tag | `2.6-pg18-trixie` |
| Base | Debian Trixie (scratch final image) |
| Architectures | `linux/amd64`, `linux/arm64` |
| Size | ~50KB |

## Contents

The image contains only the files required by CNPG ImageVolume:

```
/lib/wal2json.so
/share/extension/wal2json.control
/share/extension/wal2json--*.sql
```

## Building Locally

```bash
cd containers/wal2json
docker buildx build --platform linux/amd64,linux/arm64 -t wal2json:local .
```

## Updating

When wal2json or PostgreSQL versions change:

1. Update `PG_MAJOR` ARG in Dockerfile (if PostgreSQL version changes)
2. Update COPY paths if PostgreSQL major version changes
3. Update tags in `.github/workflows/build-wal2json.yaml`
4. Push to main - workflow builds automatically

## License

wal2json is released under the BSD-3-Clause license. See [LICENSE](LICENSE) for details.

## References

- [wal2json GitHub](https://github.com/eulerto/wal2json)
- [CNPG ImageVolume Extensions](https://cloudnative-pg.io/documentation/current/imagevolume_extensions/)
- [PGDG Apt Repository](https://www.postgresql.org/download/linux/debian/)
