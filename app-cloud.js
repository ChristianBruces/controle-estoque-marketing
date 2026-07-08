(function () {
  const cloud = () => window.ATEM_CLOUD;
  let cloudMode = false;
  let cloudProfile = null;
  let cloudSession = null;

  const originalShowItemForm = showItemForm;
  const originalShowMovementForm = showMovementForm;
  const originalRenderInventory = renderInventory;
  const originalMovementTableClick = document.querySelector('#movementTable')?.onclick;

  const unique = values => [...new Set(values.filter(Boolean))].sort((a, b) => a.localeCompare(b, 'pt-BR'));
  const areas = () => unique([...items.map(item => item.area), 'Marketing', 'Comercial']);
  const categories = () => unique([...items.map(item => item.category), 'Brindes', 'Materiais Gráficos', 'Enxovais', 'Eventos']);
  const campaigns = () => unique([...items.map(item => item.campaign), 'Acelera Aí', 'Combustível do Bem', 'Inauguração de posto']);
  const selectOptions = (values, selected = '') => values.map(value => `<option ${value === selected ? 'selected' : ''}>${value}</option>`).join('');
  const currentName = () => cloudProfile?.full_name || cloudSession?.user?.email || 'Christian Souza';
  const roleLabel = role => ({ assistant: 'Assistente', analyst: 'Analista', manager: 'Gestor' })[role] || 'Modo local';
  const canManageItems = () => !cloudMode || ['analyst', 'manager'].includes(cloudProfile?.role);
  const canApprove = () => !cloudMode || cloudProfile?.role === 'manager';

  function renderCloudStatus() {
    let box = document.querySelector('#cloudStatus');
    if (!box) {
      box = document.createElement('div');
      box.id = 'cloudStatus';
      box.className = 'cloud-status';
      document.querySelector('.top-actions')?.prepend(box);
    }

    let mobileBox = document.querySelector('#mobileCloudStatus');
    if (!mobileBox) {
      mobileBox = document.createElement('div');
      mobileBox.id = 'mobileCloudStatus';
      mobileBox.className = 'mobile-cloud-status';
      document.querySelector('.topbar')?.insertAdjacentElement('afterend', mobileBox);
    }

    if (!cloud()) {
      box.innerHTML = '<span class="offline-dot"></span><span>Modo local</span>';
      mobileBox.innerHTML = '<div><strong>Modo local</strong><small>Sincronização online indisponível neste momento.</small></div>';
      return;
    }

    if (!cloudMode) {
      box.innerHTML = '<span class="offline-dot"></span><button class="link-btn" id="cloudLogin">Entrar para sincronizar</button>';
      document.querySelector('#cloudLogin').onclick = showLoginModal;
      mobileBox.innerHTML = `
        <div>
          <strong>Estoque online</strong>
          <small>Entre para sincronizar dados entre celular, notebook e equipe.</small>
        </div>
        <button class="btn btn-primary" id="mobileCloudLogin">Entrar</button>
      `;
      document.querySelector('#mobileCloudLogin').onclick = showLoginModal;
      return;
    }

    box.innerHTML = `<span class="online-dot"></span><span>Online · ${roleLabel(cloudProfile?.role)}</span><button class="link-btn" id="cloudLogout">Sair</button>`;
    document.querySelector('#cloudLogout').onclick = signOut;
    mobileBox.innerHTML = `
      <div>
        <strong>Online Â· ${roleLabel(cloudProfile?.role)}</strong>
        <small>${currentName()}</small>
      </div>
      <button class="btn btn-light" id="mobileCloudLogout">Sair</button>
    `;
    document.querySelector('#mobileCloudLogout').onclick = signOut;
  }

  function renderProfile() {
    const name = document.querySelector('.sidebar-footer strong');
    const role = document.querySelector('.sidebar-footer small');
    if (name) name.textContent = currentName();
    if (role) role.textContent = cloudMode ? roleLabel(cloudProfile?.role) : 'Modo local';
  }

  function showLoginModal() {
    openModal(`
      <div class="modal-content">
        <h2>Entrar no estoque online</h2>
        <p>Use o e-mail e senha criados no Supabase. Ao entrar, notebook e celular passam a usar o mesmo banco.</p>
        <form id="loginForm">
          <div class="form-grid">
            <div class="field full"><label>E-mail</label><input required type="email" name="email" autocomplete="email" placeholder="seu.email@empresa.com.br"></div>
            <div class="field full"><label>Senha</label><input required type="password" name="password" autocomplete="current-password" placeholder="Sua senha"></div>
          </div>
          <div class="modal-actions">
            <button type="button" class="btn btn-light" id="cancelModal">Cancelar</button>
            <button class="btn btn-primary">Entrar e sincronizar</button>
          </div>
        </form>
      </div>
    `);
    document.querySelector('#cancelModal').onclick = closeModal;
    document.querySelector('#loginForm').onsubmit = async event => {
      event.preventDefault();
      const data = Object.fromEntries(new FormData(event.target));
      try {
        await cloud().signIn(data.email, data.password);
        closeModal();
        await startCloud();
        toast('Sincronização online ativada.');
      } catch (error) {
        toast(error.message);
      }
    };
  }

  async function loadCloudData() {
    const data = await cloud().loadData();
    items = data.items;
    movements = data.movements;
    cloudProfile = data.profile;
    renderCloudStatus();
    renderProfile();
    renderAll();
  }

  async function startCloud() {
    if (!cloud()) {
      renderCloudStatus();
      renderProfile();
      return;
    }

    try {
      cloudSession = await cloud().getSession();
      if (!cloudSession) {
        cloudMode = false;
        renderCloudStatus();
        renderProfile();
        return;
      }

      cloudMode = true;
      await loadCloudData();
    } catch (error) {
      cloudMode = false;
      renderCloudStatus();
      renderProfile();
      toast('Supabase ainda não está pronto. Execute o arquivo supabase_migration.sql no SQL Editor.');
    }
  }

  async function signOut() {
    await cloud().signOut();
    cloudMode = false;
    cloudProfile = null;
    cloudSession = null;
    items = JSON.parse(localStorage.getItem('atem-items') || 'null') || seedItems;
    movements = JSON.parse(localStorage.getItem('atem-movements') || 'null') || seedMovements;
    renderCloudStatus();
    renderProfile();
    renderAll();
    toast('Você saiu do modo online.');
  }

  function buildItemOptions(selected = '') {
    return items.map(item => `<option value="${item.id}" ${String(item.id) === String(selected) ? 'selected' : ''}>${item.code} — ${item.name} (${formatNumber(item.stock)} ${item.unit})</option>`).join('');
  }

  showItemForm = function (item) {
    if (!cloudMode) {
      originalShowItemForm(item);
      return;
    }

    if (!canManageItems()) {
      toast('Seu perfil pode consultar e movimentar, mas não editar materiais.');
      return;
    }

    const edit = Boolean(item);
    openModal(`
      <div class="modal-content">
        <h2>${edit ? 'Editar material' : 'Novo material'}</h2>
        <p>${edit ? 'Atualize o cadastro. O saldo online continua sendo calculado pelas movimentações.' : 'Cadastre o item e registre o saldo inicial rastreável.'}</p>
        <form id="itemForm">
          <div class="form-grid">
            <div class="field"><label>Código interno *</label><input required name="code" value="${item?.code || ''}" placeholder="Ex.: MKT-052"></div>
            <div class="field"><label>Nome do item *</label><input required name="name" value="${item?.name || ''}" placeholder="Nome do material"></div>
            <div class="field"><label>Categoria *</label><select name="category">${selectOptions(categories(), item?.category)}</select></div>
            <div class="field"><label>Área responsável *</label><select name="area">${selectOptions(areas(), item?.area)}</select></div>
            <div class="field"><label>${edit ? 'Saldo atual' : 'Estoque inicial'}</label><input name="stock" type="number" min="0" ${edit ? 'readonly' : ''} value="${item?.stock || 0}"></div>
            <div class="field"><label>Unidade</label><select name="unit">${selectOptions(['un.', 'kit', 'caixa', 'pacote'], item?.unit || 'un.')}</select></div>
            <div class="field"><label>Mínimo crítico *</label><input required name="minimum" type="number" min="0" value="${item?.minimum || 0}"></div>
            <div class="field"><label>Limite de atenção *</label><input required name="attention" type="number" min="0" value="${item?.attention || 0}"></div>
            <div class="field"><label>Local</label><input name="location" value="${item?.location || ''}" placeholder="Ex.: A-01"></div>
            <div class="field"><label>Fornecedor</label><input name="supplier" value="${item?.supplier || ''}" placeholder="Fornecedor"></div>
            <div class="field full"><label>Campanha</label><select name="campaign"><option value="">Sem campanha</option>${selectOptions(campaigns(), item?.campaign)}</select></div>
            <div class="field full"><label>Foto do item (URL)</label><input name="photoUrl" value="${item?.photoUrl || ''}" placeholder="Cole o link da foto, se houver"></div>
            <div class="field full"><label>Observações</label><textarea name="observations" placeholder="Detalhes importantes">${item?.observations || ''}</textarea></div>
          </div>
          <div class="modal-actions">
            <button type="button" class="btn btn-light" id="cancelModal">Cancelar</button>
            <button class="btn btn-primary">${edit ? 'Salvar alterações' : 'Cadastrar material'}</button>
          </div>
        </form>
      </div>
    `);

    document.querySelector('#cancelModal').onclick = closeModal;
    document.querySelector('#itemForm').onsubmit = async event => {
      event.preventDefault();
      const data = Object.fromEntries(new FormData(event.target));
      if (Number(data.attention) < Number(data.minimum)) {
        toast('O limite de atenção deve ser maior ou igual ao mínimo crítico.');
        return;
      }

      try {
        if (edit) await cloud().updateItem(item.id, data);
        else await cloud().createItem(data);
        await loadCloudData();
        closeModal();
        toast(edit ? 'Material atualizado online.' : 'Material cadastrado online.');
      } catch (error) {
        toast(error.message);
      }
    };
  };

  showMovementForm = function (type) {
    if (!cloudMode) {
      originalShowMovementForm(type);
      return;
    }

    if (!items.length) {
      toast('Cadastre um material antes de movimentar.');
      return;
    }

    const labels = {
      entry: ['Registrar entrada', 'Recebimento de materiais', 'Quantidade recebida'],
      exit: ['Registrar saída', 'Retirada de materiais', 'Quantidade retirada'],
      transfer: ['Transferir área', 'Altera a área responsável sem mudar o saldo', ''],
      adjust: ['Solicitar ajuste', 'O saldo só será atualizado após aprovação do gestor', 'Diferença encontrada']
    };
    const [title, description, qtyLabel] = labels[type];

    openModal(`
      <div class="modal-content">
        <h2>${title}</h2>
        <p>${description}</p>
        <form id="movementForm">
          <div class="form-grid">
            <div class="field full"><label>Material *</label><select name="itemId" required>${buildItemOptions()}</select></div>
            ${type === 'transfer'
              ? `<div class="field full"><label>Nova área responsável *</label><select name="area">${selectOptions(areas())}</select></div>`
              : `<div class="field"><label>${qtyLabel} *</label><input name="quantity" type="number" ${type === 'adjust' ? '' : 'min="1"'} required placeholder="0"></div><div class="field"><label>Data</label><input name="date" type="datetime-local" value="${new Date().toISOString().slice(0, 16)}"></div>`
            }
            <div class="field"><label>${type === 'exit' ? 'Solicitante' : 'Responsável'}</label><input name="requester" placeholder="Nome do responsável"></div>
            <div class="field"><label>Campanha</label><select name="campaign"><option value="">Sem campanha</option>${selectOptions(campaigns())}</select></div>
            <div class="field full"><label>${type === 'entry' ? 'Nota fiscal / fornecedor' : type === 'exit' ? 'Motivo / unidade solicitante' : 'Observações'}</label><textarea name="detail" placeholder="Inclua detalhes para a rastreabilidade"></textarea></div>
          </div>
          <div class="modal-actions">
            <button type="button" class="btn btn-light" id="cancelModal">Cancelar</button>
            <button class="btn btn-primary">${type === 'adjust' ? 'Enviar para aprovação' : 'Confirmar movimentação'}</button>
          </div>
        </form>
      </div>
    `);

    document.querySelector('#cancelModal').onclick = closeModal;
    document.querySelector('#movementForm').onsubmit = async event => {
      event.preventDefault();
      const data = Object.fromEntries(new FormData(event.target));
      const item = getItem(data.itemId);
      const quantity = Number(data.quantity || 0);

      if (type === 'exit' && quantity > item.stock) {
        toast(`Saldo insuficiente: há apenas ${item.stock} ${item.unit} disponíveis.`);
        return;
      }

      try {
        await cloud().registerMovement(type, { ...data, itemId: item.id, quantity });
        await loadCloudData();
        closeModal();
        toast(type === 'adjust' ? 'Ajuste enviado para aprovação.' : 'Movimentação sincronizada.');
      } catch (error) {
        toast(error.message);
      }
    };
  };

  renderInventory = function () {
    originalRenderInventory();
    if (!canManageItems()) {
      document.querySelectorAll('[data-edit-item]').forEach(button => {
        button.disabled = true;
        button.title = 'Perfil sem permissão para editar';
      });
    }
  };

  document.querySelector('#movementTable').onclick = async event => {
    if (!cloudMode) {
      originalMovementTableClick?.call(event.currentTarget, event);
      return;
    }

    const id = event.target.dataset.approve || event.target.dataset.reject;
    if (!id) return;
    const movement = movements.find(row => String(row.id) === String(id));
    if (!movement || movement.status !== 'pending') return;

    if (!canApprove()) {
      toast('Apenas gestores podem aprovar ajustes.');
      return;
    }
    try {
      await cloud().approveMovement(id, Boolean(event.target.dataset.approve));
      await loadCloudData();
      toast(event.target.dataset.approve ? 'Ajuste aprovado online.' : 'Ajuste recusado online.');
    } catch (error) {
      toast(error.message);
    }
  };

  window.addEventListener('load', () => {
    renderCloudStatus();
    renderProfile();
    startCloud();
    setInterval(() => {
      if (cloudMode) loadCloudData().catch(() => {});
    }, 20000);
  });
})();
