// API Endpoint Roots (Served via Nginx proxy from relative paths)
const API_STATS = '/api/stats';
const API_KEYS = '/api/keys';
const API_KEYS_DELETE = '/api/keys/delete';

// UI Elements
const valActiveKeys = document.getElementById('val-active-keys');
const valTotalSpend = document.getElementById('val-total-spend');
const valTotalBudget = document.getElementById('val-total-budget');
const modelsChecklist = document.getElementById('models-checklist');
const keysTableBody = document.getElementById('keys-table-body');
const keyGeneratorForm = document.getElementById('key-generator-form');
const btnSubmitKey = document.getElementById('btn-submit-key');
const btnSpinner = document.getElementById('btn-spinner');
const btnRefreshKeys = document.getElementById('btn-refresh-keys');
const iconRefresh = btnRefreshKeys.querySelector('.icon-refresh');

// Modal Elements
const modalKeyDisplay = document.getElementById('modal-key-display');
const newKeyValue = document.getElementById('new-key-value');
const btnModalCopy = document.getElementById('btn-modal-copy');
const copyBtnText = document.getElementById('copy-btn-text');
const btnModalClose = document.getElementById('btn-modal-close');

// Global state holding available models
let availableModels = [];

// Init Page
document.addEventListener('DOMContentLoaded', () => {
  fetchDashboardData();
  
  // Register Events
  keyGeneratorForm.addEventListener('submit', handleGenerateKey);
  btnRefreshKeys.addEventListener('click', () => {
    iconRefresh.style.transform = 'rotate(360deg)';
    fetchDashboardData();
    setTimeout(() => { iconRefresh.style.transform = ''; }, 400);
  });
  
  // Modal Events
  btnModalCopy.addEventListener('click', () => {
    copyToClipboard(newKeyValue.innerText);
    copyBtnText.innerText = 'Copied!';
    showToast('Key copied to clipboard!', 'success');
    setTimeout(() => { copyBtnText.innerText = 'Copy Key'; }, 2000);
  });
  
  btnModalClose.addEventListener('click', () => {
    modalKeyDisplay.style.display = 'none';
  });
});

// Toast Manager
function showToast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  
  const icon = document.createElement('span');
  icon.innerHTML = type === 'success' ? '✓' : type === 'error' ? '✗' : 'ℹ';
  icon.style.fontWeight = 'bold';
  
  const text = document.createElement('span');
  text.className = 'toast-message';
  text.innerText = message;
  
  toast.appendChild(icon);
  toast.appendChild(text);
  container.appendChild(toast);
  
  // Auto remove after animation completes
  setTimeout(() => {
    toast.remove();
  }, 4000);
}

// Fetch all dashboard stats and keys
async function fetchDashboardData() {
  await Promise.all([
    loadStats(),
    loadKeys()
  ]);
}

// Load summary stats & available models
async function loadStats() {
  try {
    const response = await fetch(API_STATS);
    if (!response.ok) throw new Error('Network response error fetching stats');
    const data = await response.json();
    
    valActiveKeys.innerText = data.activeKeys ?? 0;
    valTotalSpend.innerText = `$${parseFloat(data.totalSpend ?? 0).toFixed(4)}`;
    valTotalBudget.innerText = `$${parseFloat(data.totalBudget ?? 0).toFixed(2)}`;
    
    // Set models checklist if changed
    if (JSON.stringify(availableModels) !== JSON.stringify(data.models)) {
      availableModels = data.models || [];
      renderModelsChecklist(availableModels);
    }
  } catch (err) {
    console.error('Error fetching stats:', err);
    showToast('Failed to load gateway statistics', 'error');
  }
}

// Render model selection checklist
function renderModelsChecklist(models) {
  modelsChecklist.innerHTML = '';
  if (models.length === 0) {
    modelsChecklist.innerHTML = '<span class="loading-placeholder">No models available on LiteLLM</span>';
    return;
  }
  
  models.forEach(model => {
    const label = document.createElement('label');
    label.className = 'model-checkbox-label';
    
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.value = model;
    checkbox.checked = true; // Checked by default
    
    const span = document.createElement('span');
    span.innerText = model;
    
    label.appendChild(checkbox);
    label.appendChild(span);
    modelsChecklist.appendChild(label);
  });
}

// Load active keys list from backend
async function loadKeys() {
  try {
    const response = await fetch(API_KEYS);
    if (!response.ok) throw new Error('Network response error fetching keys');
    const data = await response.json();
    const keys = data.keys || [];
    
    renderKeysTable(keys);
  } catch (err) {
    console.error('Error fetching keys:', err);
    keysTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="text-center table-loading" style="color: var(--color-danger)">
          Error connecting to Admin Backend API. Ensure containers are running.
        </td>
      </tr>
    `;
    showToast('Failed to load virtual keys list', 'error');
  }
}

// Populate keys table
function renderKeysTable(keys) {
  if (keys.length === 0) {
    keysTableBody.innerHTML = `
      <tr>
        <td colspan="6" class="text-center table-loading">
          No virtual keys found in database. Use the generator to create one.
        </td>
      </tr>
    `;
    return;
  }
  
  keysTableBody.innerHTML = '';
  keys.forEach(k => {
    const tr = document.createElement('tr');
    
    // Alias column
    const tdAlias = document.createElement('td');
    const aliasSpan = document.createElement('span');
    aliasSpan.className = 'key-alias-name';
    aliasSpan.innerText = k.key_alias || 'Unnamed Key';
    const dateSpan = document.createElement('span');
    dateSpan.className = 'key-created-date';
    dateSpan.innerText = k.created_at ? new Date(k.created_at).toLocaleString() : 'N/A';
    tdAlias.appendChild(aliasSpan);
    tdAlias.appendChild(dateSpan);
    
    // Key Token column (masked with copy button)
    const tdKey = document.createElement('td');
    const keyWrapper = document.createElement('span');
    keyWrapper.className = 'key-token-wrapper';
    
    const keyToken = document.createElement('code');
    keyToken.className = 'key-token';
    // Display masked token
    keyToken.innerText = k.token || k.key || '••••••••••••';
    
    const btnCopy = document.createElement('button');
    btnCopy.className = 'btn-inline-copy';
    btnCopy.title = 'Copy Masked Key';
    btnCopy.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
      </svg>
    `;
    btnCopy.addEventListener('click', () => {
      copyToClipboard(k.token || k.key);
      showToast('Key copied to clipboard!', 'success');
    });
    
    keyWrapper.appendChild(keyToken);
    keyWrapper.appendChild(btnCopy);
    tdKey.appendChild(keyWrapper);
    
    // Spend column
    const tdSpend = document.createElement('td');
    const currentSpend = parseFloat(k.spend || 0).toFixed(6);
    const maxBudget = k.max_budget ? `$${parseFloat(k.max_budget).toFixed(2)}` : 'Unlimited';
    tdSpend.innerHTML = `<strong>$${currentSpend}</strong> <span style="color: var(--text-muted); font-size: 12px;">/ ${maxBudget}</span>`;
    
    // Limits (RPM/TPM) column
    const tdLimits = document.createElement('td');
    const limitContainer = document.createElement('div');
    limitContainer.className = 'limit-item';
    
    const rpmVal = k.rpm_limit ? `${k.rpm_limit} RPM` : 'Unlimited RPM';
    const tpmVal = k.tpm_limit ? `${k.tpm_limit} TPM` : 'Unlimited TPM';
    
    limitContainer.innerHTML = `
      <div><span class="limit-tag">${rpmVal}</span></div>
      <div><span class="limit-tag">${tpmVal}</span></div>
    `;
    tdLimits.appendChild(limitContainer);
    
    // Allowed Models column
    const tdModels = document.createElement('td');
    const modelsContainer = document.createElement('div');
    modelsContainer.className = 'model-tags-container';
    
    const modelsList = k.models || k.allowed_models || [];
    if (modelsList.length === 0) {
      modelsContainer.innerHTML = '<span style="font-size: 12px; color: var(--text-muted);">All Models</span>';
    } else {
      modelsList.forEach(m => {
        const tag = document.createElement('span');
        tag.className = 'model-tag';
        tag.innerText = m;
        modelsContainer.appendChild(tag);
      });
    }
    tdModels.appendChild(modelsContainer);
    
    // Action column (Delete)
    const tdActions = document.createElement('td');
    tdActions.className = 'text-right';
    
    const btnDel = document.createElement('button');
    btnDel.className = 'btn btn-delete';
    btnDel.innerText = 'Revoke';
    btnDel.addEventListener('click', () => handleDeleteKey(k.token || k.key, k.key_alias));
    tdActions.appendChild(btnDel);
    
    tr.appendChild(tdAlias);
    tr.appendChild(tdKey);
    tr.appendChild(tdSpend);
    tr.appendChild(tdLimits);
    tr.appendChild(tdModels);
    tr.appendChild(tdActions);
    keysTableBody.appendChild(tr);
  });
}

// Generate Key Submit handler
async function handleGenerateKey(e) {
  e.preventDefault();
  
  // Get values
  const keyAlias = document.getElementById('key-alias').value.trim();
  const maxBudget = document.getElementById('max-budget').value;
  const rpmLimit = document.getElementById('rpm-limit').value;
  const tpmLimit = document.getElementById('tpm-limit').value;
  
  // Get selected models
  const selectedModels = [];
  const checkedBoxes = modelsChecklist.querySelectorAll('input[type="checkbox"]:checked');
  checkedBoxes.forEach(cb => selectedModels.push(cb.value));
  
  if (selectedModels.length === 0) {
    showToast('Please select at least one allowed model.', 'error');
    return;
  }
  
  // Set UI state to loading
  btnSubmitKey.disabled = true;
  btnSpinner.style.display = 'block';
  
  try {
    const payload = {
      key_alias: keyAlias,
      models: selectedModels,
      max_budget: maxBudget ? parseFloat(maxBudget) : null,
      rpm_limit: rpmLimit ? parseInt(rpmLimit, 10) : null,
      tpm_limit: tpmLimit ? parseInt(tpmLimit, 10) : null
    };
    
    const response = await fetch(API_KEYS, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });
    
    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.details || errorData.error || 'Failed to generate key');
    }
    
    const data = await response.json();
    
    // Clear inputs
    document.getElementById('key-alias').value = '';
    document.getElementById('max-budget').value = '';
    document.getElementById('rpm-limit').value = '';
    document.getElementById('tpm-limit').value = '';
    
    // Show newly created key in modal
    newKeyValue.innerText = data.key || data.token || 'Error: Key not returned';
    modalKeyDisplay.style.display = 'flex';
    
    showToast('Virtual key generated successfully!', 'success');
    
    // Reload data
    fetchDashboardData();
  } catch (err) {
    console.error('Error generating key:', err);
    showToast(`Error: ${err.message}`, 'error');
  } finally {
    btnSubmitKey.disabled = false;
    btnSpinner.style.display = 'none';
  }
}

// Revoke/Delete Key handler
async function handleDeleteKey(key, alias) {
  const confirmMsg = `Are you sure you want to revoke the API key for "${alias || 'Unnamed Key'}"? This key will immediately stop working.`;
  if (!confirm(confirmMsg)) return;
  
  try {
    const response = await fetch(API_KEYS_DELETE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ key })
    });
    
    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.details || errorData.error || 'Failed to revoke key');
    }
    
    showToast(`Successfully revoked key for "${alias}"`, 'success');
    fetchDashboardData();
  } catch (err) {
    console.error('Error deleting key:', err);
    showToast(`Failed to revoke key: ${err.message}`, 'error');
  }
}

// Helper: Copy string to clipboard
function copyToClipboard(text) {
  if (!text) return;
  const el = document.createElement('textarea');
  el.value = text;
  document.body.appendChild(el);
  el.select();
  document.execCommand('copy');
  document.body.removeChild(el);
}
