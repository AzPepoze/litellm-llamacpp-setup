const express = require('express');
const axios = require('axios');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 5000;
const LITELLM_API_BASE = process.env.LITELLM_API_BASE || 'http://litellm:4000';
const LITELLM_MASTER_KEY = process.env.LITELLM_MASTER_KEY || 'sk-super-secret-key';

app.use(cors());
app.use(express.json());

// Create axios instance pre-configured for LiteLLM Authentication
const litellmClient = axios.create({
  baseURL: LITELLM_API_BASE,
  headers: {
    'Authorization': `Bearer ${LITELLM_MASTER_KEY}`,
    'Content-Type': 'application/json'
  }
});

// GET /api/keys - Retrieve all virtual keys
app.get('/api/keys', async (req, res) => {
  try {
    const response = await litellmClient.get('/key/list');
    res.json(response.data);
  } catch (error) {
    console.error('Error fetching keys from LiteLLM:', error.message);
    res.status(500).json({ 
      error: 'Failed to fetch keys from LiteLLM', 
      details: error.response?.data || error.message 
    });
  }
});

// POST /api/keys - Generate a new virtual key
app.post('/api/keys', async (req, res) => {
  try {
    const { key_alias, models, max_budget, tpm_limit, rpm_limit } = req.body;

    const requestBody = {
      models: Array.isArray(models) ? models : [],
    };

    if (key_alias) requestBody.key_alias = key_alias;
    
    // Parse limits and budget if provided
    if (max_budget !== undefined && max_budget !== null && max_budget !== '') {
      requestBody.max_budget = parseFloat(max_budget);
    }
    if (tpm_limit !== undefined && tpm_limit !== null && tpm_limit !== '') {
      requestBody.tpm_limit = parseInt(tpm_limit, 10);
    }
    if (rpm_limit !== undefined && rpm_limit !== null && rpm_limit !== '') {
      requestBody.rpm_limit = parseInt(rpm_limit, 10);
    }

    const response = await litellmClient.post('/key/generate', requestBody);
    res.json(response.data);
  } catch (error) {
    console.error('Error generating key in LiteLLM:', error.message);
    res.status(500).json({ 
      error: 'Failed to generate key in LiteLLM', 
      details: error.response?.data || error.message 
    });
  }
});

// POST /api/keys/delete - Revoke a virtual key
app.post('/api/keys/delete', async (req, res) => {
  try {
    const { key } = req.body;
    if (!key) {
      return res.status(400).json({ error: 'Missing key to delete' });
    }

    const response = await litellmClient.post('/key/delete', {
      keys: [key]
    });
    res.json(response.data);
  } catch (error) {
    console.error('Error deleting key in LiteLLM:', error.message);
    res.status(500).json({ 
      error: 'Failed to delete key in LiteLLM', 
      details: error.response?.data || error.message 
    });
  }
});

// GET /api/stats - Dynamic server telemetry & model options
app.get('/api/stats', async (req, res) => {
  try {
    const response = await litellmClient.get('/key/list');
    const keysData = response.data;
    const keys = keysData.keys || [];

    let totalSpend = 0;
    let totalBudget = 0;
    const activeKeys = keys.length;

    keys.forEach(k => {
      totalSpend += parseFloat(k.spend || 0);
      if (k.max_budget) {
        totalBudget += parseFloat(k.max_budget);
      }
    });

    res.json({
      activeKeys,
      totalSpend: parseFloat(totalSpend.toFixed(6)),
      totalBudget: parseFloat(totalBudget.toFixed(2)),
      models: ['tinyllama', 'qwen-small'] // Exposed local models
    });
  } catch (error) {
    console.error('Error fetching stats from LiteLLM:', error.message);
    res.status(500).json({ 
      error: 'Failed to fetch stats from LiteLLM', 
      details: error.response?.data || error.message 
    });
  }
});

app.listen(PORT, () => {
  console.log(`Admin backend server running on port ${PORT}`);
});
