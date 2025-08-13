const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// log all requests
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`${timestamp} ${req.method} ${req.url} - ${req.ip}`);
  next();
});

app.get('/', (req, res) => {
  res.send('Hello World!');
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    uptime: process.uptime(),
  });
});

app.get('/load-test', (req, res) => {
  const iterations = parseInt(req.query.iterations) || 1000000;
  let result = 0;
  
  const start = Date.now();
  for (let i = 0; i < iterations; i++) {
    result += Math.sqrt(i) * Math.random();
  }
  const duration = Date.now() - start;
  
  res.json({
    message: 'Load test endpoint',
    iterations: iterations,
    result: Math.floor(result),
    duration: `${duration}ms`,
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running at http://0.0.0.0:${PORT}`);
});