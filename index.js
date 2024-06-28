const express = require('express');
const httpProxy = require('http-proxy');
const app = express();
const proxy = httpProxy.createProxyServer({});

app.use((req, res) => {
  proxy.web(req, res, { target: 'http://123.193.116.33:8000' }, (error) => {
    res.status(500).send('Proxy error: ' + error.message);
  });
});

app.listen(process.env.PORT || 3000, () => {
  console.log(`Server is running on port ${process.env.PORT || 3000}`);
});
