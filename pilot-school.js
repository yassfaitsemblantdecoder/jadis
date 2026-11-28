export function installPilotSchool({ api, status, reconnect, block, report }) {
  const section = document.querySelector('#pilot-school');
  const form = section.querySelector('#pilot-school-form');
  const catalog = form.elements.institution_id;
  const save = form.querySelector('[type=submit]');
  const list = section.querySelector('#pilot-school-entries');
  const search = section.querySelector('#pilot-school-discover');
  const anchor = search.elements.entry;
  const discover = search.querySelector('[type=submit]');
  const matches = section.querySelector('#pilot-school-matches');
  const schoolStatus = section.querySelector('#pilot-school-status');
  const searchStatus = section.querySelector('#pilot-school-search-status');

  let generation = 0;
  let working = false;
  let discoverable = false;
  let dataReady = false;
  let institutions = new Set();
  let rows = [];
  let anchors = new Map();

  function rpc(action, params = {}) {
    return api('/rest/v1/rpc/beta_pilot_school', { method: 'POST', body: { action, ...params } });
  }

  function entryKey(row) {
    return row.institution_id + ':' + row.academic_year;
  }

  function entryParams(row) {
    return { institution_id: row.institution_id, academic_year: row.academic_year };
  }

  function schoolYear(year) {
    return year + '–' + (year + 1);
  }

  function setOptions(select, placeholder, options, previous = '') {
    select.replaceChildren(new Option(placeholder, ''), ...options);
    if (options.some(option => option.value === previous)) select.value = previous;
  }

  function syncControls() {
    catalog.disabled = working || !dataReady || catalog.options.length <= 1;
    anchor.disabled = working || !dataReady || !discoverable || anchors.size === 0;
    save.disabled = working || !dataReady || catalog.options.length <= 1;
    discover.disabled = working || !dataReady || !discoverable || anchors.size === 0;
    section.querySelectorAll('[data-pilot-action]').forEach(button => { button.disabled = working; });
  }

  async function perform(action) {
    if (working || !dataReady) return;
    const current = generation;
    working = true;
    syncControls();
    try {
      await action(current);
    } catch (error) {
      if (current === generation) status(error.message);
    } finally {
      if (current === generation) {
        working = false;
        syncControls();
      }
    }
  }

  function button(parent, label, action) {
    const element = document.createElement('button');
    element.type = 'button';
    element.dataset.pilotAction = '';
    element.textContent = label;
    element.onclick = () => perform(action);
    parent.append(element);
  }

  function renderRows(entries, preferredAnchor = '') {
    rows = entries;
    list.replaceChildren();
    anchors = new Map();
    for (const row of entries) {
      const card = document.createElement('article');
      const title = document.createElement('strong');
      const privacy = document.createElement('p');
      const available = institutions.has(row.institution_id);
      title.textContent = row.name + ' · ' + schoolYear(row.academic_year);
      privacy.textContent = 'Privée';
      if (!available) {
        privacy.textContent = 'Cet établissement n’est plus disponible pour la découverte.';
      } else if (row.discoverable) {
        privacy.textContent = discoverable ? 'Découverte autorisée pour cette année'
          : 'Autorisation pour cette année enregistrée. Ton profil reste privé.';
      }
      card.append(title, privacy);
      if (available || row.discoverable) {
        button(card, row.discoverable ? 'Désactiver la découverte' : 'Activer la découverte', async current => {
          await rpc('save', { ...entryParams(row), discoverable: !row.discoverable });
          if (current !== generation) return;
          await refreshRows(current);
          if (current === generation) status('Préférence de découverte enregistrée.');
        });
      }
      button(card, 'Retirer', async current => {
        const removed = await rpc('delete', entryParams(row));
        if (current !== generation) return;
        await refreshRows(current);
        if (current === generation) {
          status(removed ? 'Année retirée de ton parcours.' : 'Cette année ne figure plus dans ton parcours.');
        }
      });
      list.append(card);
      if (available && row.discoverable) anchors.set(entryKey(row), row);
    }
    if (!entries.length) list.textContent = 'Ton parcours scolaire est vide.';

    const options = [...anchors].map(([key, row]) => new Option(row.name + ' · ' + schoolYear(row.academic_year), key));
    const selected = preferredAnchor || anchor.value;
    setOptions(anchor, 'Choisir une année de mon parcours', options, selected);
    if (!anchor.value && options.length === 1) anchor.value = options[0].value;
    searchStatus.textContent = options.length === 0 ? 'Autorise la découverte pour au moins une année.' : '';
    syncControls();
  }

  async function refreshRows(current, preferredAnchor) {
    // Clear earlier results before reloading the choice of years.
    matches.replaceChildren();
    const entries = await rpc('list');
    if (current === generation) renderRows(entries, preferredAnchor);
  }

  form.onsubmit = event => {
    event.preventDefault();
    const entry = { institution_id: catalog.value, academic_year: form.elements.academic_year.valueAsNumber };
    const key = entryKey(entry);
    if (rows.some(row => entryKey(row) === key)) {
      status('Cette année figure déjà dans ton parcours. Utilise ses commandes pour modifier sa visibilité.');
      return;
    }
    const discoverableForYear = form.elements.discoverable.checked;
    return perform(async current => {
      await rpc('save', { ...entry, discoverable: discoverableForYear });
      if (current !== generation) return;
      form.reset();
      await refreshRows(current, discoverableForYear ? key : undefined);
      if (current === generation) status('Année ajoutée à ton parcours.');
    });
  };

  search.onsubmit = event => {
    event.preventDefault();
    const row = anchors.get(anchor.value);
    if (!row || !discoverable) return;
    return perform(async current => {
      matches.replaceChildren();
      const results = await rpc('discover', entryParams(row));
      if (current !== generation) return;
      if (!results.length) matches.textContent = 'Aucun camarade à afficher pour cet établissement et cette année.';
      for (const result of results) {
        const card = document.createElement('article');
        const name = document.createElement('strong');
        const description = document.createElement('p');
        name.textContent = result.display_name;
        description.textContent = result.institution_name + ' · ' + schoolYear(result.academic_year);
        card.append(name, description);
        button(card, 'Se reconnecter', () => reconnect(result.person_id));
        button(card, 'Bloquer', async () => { await block(result.person_id); card.remove(); });
        button(card, 'Signaler', () => report(result.person_id));
        matches.append(card);
      }
    });
  };
  anchor.onchange = () => matches.replaceChildren();

  return {
    async show(profileDiscoverable) {
      const current = ++generation;
      working = true;
      dataReady = false;
      discoverable = profileDiscoverable;
      section.hidden = false;
      search.hidden = !discoverable;
      matches.replaceChildren();
      syncControls();
      schoolStatus.textContent = 'Chargement du parcours scolaire…';
      try {
        const [schools, entries] = await Promise.all([rpc('catalog'), rpc('list')]);
        if (current !== generation) return;
        institutions = new Set(schools.map(school => school.id));
        const options = schools.map(school => new Option(school.uai ? school.name + ' · ' + school.uai : school.name, school.id));
        setOptions(catalog, 'Choisir un établissement', options, catalog.value);
        dataReady = true;
        renderRows(entries);
        schoolStatus.textContent = options.length ? '' : 'Aucun établissement du pilote n’est disponible.';
      } catch (error) {
        if (current !== generation) return;
        institutions.clear();
        rows = [];
        list.replaceChildren();
        setOptions(catalog, 'Choisir un établissement', []);
        search.hidden = true;
        schoolStatus.textContent = 'Le parcours scolaire est indisponible. Reconnecte-toi pour réessayer.';
      } finally {
        if (current === generation) {
          working = false;
          syncControls();
        }
      }
    },
    reset() {
      generation++;
      working = false;
      dataReady = false;
      discoverable = false;
      institutions.clear();
      rows = [];
      anchors.clear();
      section.hidden = true;
      search.hidden = true;
      form.reset();
      search.reset();
      setOptions(catalog, 'Choisir un établissement', []);
      setOptions(anchor, 'Choisir une année de mon parcours', []);
      list.replaceChildren();
      matches.replaceChildren();
      schoolStatus.textContent = '';
      searchStatus.textContent = '';
      syncControls();
    },
  };
}
