(function () {
  const config = window.ATEM_SUPABASE_CONFIG;

  if (!config?.url || !config?.anonKey || !window.supabase) {
    window.ATEM_CLOUD = null;
    return;
  }

  const client = window.supabase.createClient(config.url, config.anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false
    }
  });

  const mapItem = row => ({
    id: row.id,
    code: row.code,
    name: row.name,
    category: row.category || 'Sem categoria',
    area: row.area || 'Sem área',
    stock: Number(row.stock || 0),
    minimum: Number(row.minimum_critical || 0),
    attention: Number(row.attention_limit || 0),
    unit: row.unit || 'un.',
    location: row.location || '',
    supplier: row.supplier || '',
    campaign: row.campaign || '',
    photoUrl: row.photo_url || '',
    description: row.description || '',
    observations: row.observations || '',
    icon: row.icon || '●'
  });

  const mapMovement = row => ({
    id: row.id,
    type: row.type,
    itemId: row.item_id,
    quantity: Number(row.quantity || 0),
    date: row.created_at,
    user: row.user_name || 'Usuário',
    detail: row.detail || '',
    status: row.status === 'effective' ? undefined : row.status,
    approvedBy: row.approved_by_name,
    approvedAt: row.approved_at
  });

  async function requireOk(result, fallbackMessage) {
    if (result.error) {
      throw new Error(result.error.message || fallbackMessage);
    }
    return result.data;
  }

  window.ATEM_CLOUD = {
    client,

    async getSession() {
      const { data } = await client.auth.getSession();
      return data.session;
    },

    async signIn(email, password) {
      return requireOk(await client.auth.signInWithPassword({ email, password }), 'Não foi possível entrar.');
    },

    async signOut() {
      await client.auth.signOut();
    },

    async loadData() {
      const [itemsResult, movementsResult, profileResult] = await Promise.all([
        client.from('inventory_items').select('*').order('name'),
        client.from('inventory_movements').select('*').order('created_at', { ascending: false }).limit(500),
        client.from('profiles').select('full_name,role').maybeSingle()
      ]);

      return {
        items: (await requireOk(itemsResult, 'Erro ao carregar materiais.')).map(mapItem),
        movements: (await requireOk(movementsResult, 'Erro ao carregar movimentações.')).map(mapMovement),
        profile: profileResult.error ? null : profileResult.data
      };
    },

    async createItem(payload) {
      return requireOk(await client.rpc('app_create_item', {
        p_code: payload.code,
        p_name: payload.name,
        p_category_name: payload.category,
        p_department_name: payload.area,
        p_campaign_name: payload.campaign || null,
        p_supplier_name: payload.supplier || null,
        p_initial_stock: Number(payload.stock || 0),
        p_minimum_critical: Number(payload.minimum || 0),
        p_attention_limit: Number(payload.attention || 0),
        p_unit: payload.unit || 'un.',
        p_location: payload.location || null,
        p_description: payload.description || null,
        p_observations: payload.observations || null,
        p_photo_url: payload.photoUrl || null
      }), 'Erro ao cadastrar material.');
    },

    async updateItem(id, payload) {
      return requireOk(await client.rpc('app_update_item', {
        p_item_id: id,
        p_code: payload.code,
        p_name: payload.name,
        p_category_name: payload.category,
        p_department_name: payload.area,
        p_campaign_name: payload.campaign || null,
        p_supplier_name: payload.supplier || null,
        p_minimum_critical: Number(payload.minimum || 0),
        p_attention_limit: Number(payload.attention || 0),
        p_unit: payload.unit || 'un.',
        p_location: payload.location || null,
        p_description: payload.description || null,
        p_observations: payload.observations || null,
        p_photo_url: payload.photoUrl || null
      }), 'Erro ao atualizar material.');
    },

    async registerMovement(type, payload) {
      return requireOk(await client.rpc('app_register_movement', {
        p_type: type,
        p_item_id: payload.itemId,
        p_quantity: Number(payload.quantity || 0),
        p_detail: payload.detail || null,
        p_requester: payload.requester || null,
        p_campaign_name: payload.campaign || null,
        p_new_department_name: payload.area || null
      }), 'Erro ao registrar movimentação.');
    },

    async approveMovement(id, approved) {
      return requireOk(await client.rpc('app_approve_movement', {
        p_movement_id: id,
        p_approved: approved
      }), 'Erro ao avaliar ajuste.');
    }
  };
})();
