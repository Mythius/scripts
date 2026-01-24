echo "Exposing to https://test.msouthwick.com"
ssh -N -R 127.0.0.1:18080:127.0.0.1:$1 matthias@msouthwick.com
