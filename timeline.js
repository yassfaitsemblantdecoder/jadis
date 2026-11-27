const categories = {
  school: 'Établissement',
  neighborhood: 'Quartier',
  work: 'Entreprise',
  camp: 'Colonie de vacances',
  association: 'Association',
  venue: 'Lieu de sortie',
  other: 'Autre lieu',
};

export function installTimeline({ api, status, reconnect, block, report, onEntries }) {
  const section = document.querySelector('#life-timeline');
  const form = section.querySelector('#timeline-entry');
  const memory = section.querySelector('#memory-search');
  const list = section.querySelector('#timeline-entries');
  const matches = section.querySelector('#memory-matches');
  const noticeList = section.querySelector('#search-notice-list');
  const noticeSection = section.querySelector('#search-notices');
  const saveNotice = section.querySelector('#save-notice');
  let editing = null;
  let generation = 0;

  const rpc = (name, body) => api('/rest/v1/rpc/' + name, { method: 'POST', body });

  function button(parent, label, action) {
    const element = document.createElement('button');
    element.type = 'button';
    element.textContent = label;
    element.onclick = async () => {
      element.disabled = true;
      const current = generation;
      try {
        await action();
      } catch (error) {
        if (current === generation) status(error.message);
      } finally {
        element.disabled = false;
      }
    };
    parent.append(element);
  }

  function stopEditing() {
    editing = null;
    form.reset();
    form.querySelector('[type=submit]').textContent = 'Ajouter à ma frise';
    section.querySelector('#timeline-cancel').hidden = true;
  }

  function render(rows) {
    list.replaceChildren();
    const select = memory.elements.entry;
    const selected = select.value;
    select.replaceChildren();
    for (const row of rows) {
      const article = document.createElement('article');
      article.className = 'timeline-record';
      const title = document.createElement('strong');
      title.textContent = row.place + ' · ' + row.city;
      const description = document.createElement('p');
      description.textContent = categories[row.kind] + ' · ' + row.start_year + '–' + row.end_year
        + ' · ' + (row.visible ? 'Activée pour la découverte' : 'Privée');
      article.append(title, description);
      button(article, 'Modifier', () => {
        editing = row.id;
        for (const name of ['kind', 'place', 'city', 'start_year', 'end_year']) {
          form.elements[name].value = row[name];
        }
        form.elements.visible.checked = row.visible;
        form.querySelector('[type=submit]').textContent = 'Enregistrer les modifications';
        section.querySelector('#timeline-cancel').hidden = false;
        form.elements.place.focus();
      });
      button(article, 'Retirer', async () => {
        const current = generation;
        await rpc('beta_timeline', { action: 'delete', entry_id: row.id });
        if (current !== generation) return;
        if (editing === row.id) stopEditing();
        matches.replaceChildren();
        await refresh();
      });
      list.append(article);

      if (row.visible) select.add(new Option(title.textContent, row.id));
    }
    if ([...select.options].some(option => option.value === selected)) select.value = selected;
    memory.querySelector('[type=submit]').disabled = select.length === 0;
    saveNotice.disabled = select.length === 0;
    if (!rows.length) list.textContent = 'Ta frise est vide.';
    onEntries(rows);
  }

  async function refresh() {
    const current = generation;
    const rows = await rpc('beta_timeline', { action: 'list' });
    if (current !== generation) return;
    render(rows);
    await refreshNotices();
  }

  function memorySelection() {
    const year = memory.elements.year.valueAsNumber;
    return { entry_id: memory.elements.entry.value, memory_year: Number.isNaN(year) ? null : year };
  }

  async function refreshNotices() {
    const current = generation;
    const rows = await rpc('beta_search_notices', { action: 'list' });
    if (current !== generation) return;
    noticeList.replaceChildren();
    noticeSection.hidden = rows.length === 0;
    for (const row of rows) {
      const article = document.createElement('article');
      const label = document.createElement('strong');
      label.textContent = row.place + ' · ' + row.city + (row.memory_year ? ' · ' + row.memory_year : '');
      article.append(label);
      if (!memory.hidden && row.available) {
        button(article, 'Relancer cette recherche', () => {
          memory.elements.entry.value = row.entry_id;
          memory.elements.year.value = row.memory_year ?? '';
          memory.requestSubmit();
        });
      }
      button(article, 'Effacer la recherche', async () => {
        await rpc('beta_search_notices', { action: 'delete', notice_id: row.id });
        if (current === generation) await refreshNotices();
      });
      noticeList.append(article);
    }
  }

  saveNotice.onclick = async () => {
    if (!memory.reportValidity()) return;
    const current = generation;
    saveNotice.disabled = true;
    try {
      await rpc('beta_search_notices', { action: 'save', ...memorySelection() });
      if (current !== generation) return;
      await refreshNotices();
      if (current === generation) status('Recherche enregistrée en privé.');
    } catch (error) {
      if (current === generation) status(error.message);
    } finally {
      saveNotice.disabled = memory.elements.entry.length === 0;
    }
  };

  section.querySelector('#timeline-cancel').onclick = stopEditing;
  form.onsubmit = async event => {
    event.preventDefault();
    const submit = form.querySelector('[type=submit]');
    const current = generation;
    const fields = new FormData(form);
    const details = Object.fromEntries(fields);
    details.visible = fields.has('visible');
    submit.disabled = true;
    try {
      await rpc('beta_timeline', { action: 'save', entry_id: editing, details });
      if (current !== generation) return;
      stopEditing();
      matches.replaceChildren();
      await refresh();
      if (current === generation) status('Étape du parcours enregistrée.');
    } catch (error) {
      if (current === generation) status(error.message);
    } finally {
      submit.disabled = false;
    }
  };

  memory.onsubmit = async event => {
    event.preventDefault();
    const submit = memory.querySelector('[type=submit]');
    const current = generation;
    matches.replaceChildren();
    submit.disabled = true;
    try {
      const rows = await rpc('beta_timeline_crossings', memorySelection());
      if (current !== generation) return;
      if (!rows.length) matches.textContent = 'Aucun croisement à afficher pour ce souvenir.';
      for (const row of rows) {
        const article = document.createElement('article');
        const title = document.createElement('strong');
        title.textContent = row.display_name;
        const period = document.createElement('p');
        period.textContent = row.first_common_year === row.last_common_year
          ? 'Année commune · ' + row.first_common_year
          : 'Période commune · ' + row.first_common_year + '–' + row.last_common_year;
        article.append(title, period);
        button(article, 'Se reconnecter', () => reconnect(row.person_id));
        button(article, 'Bloquer', async () => { await block(row.person_id); article.remove(); });
        button(article, 'Signaler', () => report(row.person_id));
        matches.append(article);
      }
    } catch (error) {
      if (current === generation) status(error.message);
    } finally {
      submit.disabled = memory.elements.entry.length === 0;
    }
  };

  return {
    async show(discoverable) {
      section.hidden = false;
      memory.hidden = !discoverable;
      matches.replaceChildren();
      try {
        await refresh();
      } catch (error) {
        if (!section.hidden) list.textContent = 'Frise indisponible. Reconnectez-vous pour réessayer.';
      }
    },
    reset() {
      generation++;
      section.hidden = true;
      memory.hidden = true;
      memory.reset();
      memory.elements.entry.replaceChildren();
      noticeList.replaceChildren();
      noticeSection.hidden = true;
      matches.replaceChildren();
      list.replaceChildren();
      stopEditing();
    },
  };
}
