async function preparePhoto(file) {
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 5 * 1024 * 1024) {
    throw Error('Choisis une photo JPEG, PNG ou WebP de 5 Mo maximum.');
  }
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 192 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  const context = canvas.getContext('2d');
  try {
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  } finally {
    bitmap.close();
  }
  const rgba = context.getImageData(0, 0, canvas.width, canvas.height).data;
  let rgb = '';
  for (let i = 0; i < rgba.length; i += 4) {
    rgb += String.fromCharCode(rgba[i], rgba[i + 1], rgba[i + 2]);
  }
  return { width: canvas.width, height: canvas.height, pixels: btoa(rgb) };
}

function renderPhoto(photo, caption) {
  const canvas = document.createElement('canvas');
  canvas.width = photo.width;
  canvas.height = photo.height;
  canvas.className = 'capsule-photo';
  canvas.setAttribute('role', 'img');
  canvas.setAttribute('aria-label', caption);
  const context = canvas.getContext('2d');
  const data = context.createImageData(photo.width, photo.height);
  const bytes = atob(photo.pixels);
  for (let source = 0, destination = 0; source < bytes.length; source += 3, destination += 4) {
    data.data[destination] = bytes.charCodeAt(source);
    data.data[destination + 1] = bytes.charCodeAt(source + 1);
    data.data[destination + 2] = bytes.charCodeAt(source + 2);
    data.data[destination + 3] = 255;
  }
  context.putImageData(data, 0, 0);
  return canvas;
}

export function installCapsules({ api, status, connections, report }) {
  const root = document.querySelector('#capsules');
  const creation = root.querySelector('#capsule-create');
  const list = root.querySelector('#capsule-list');
  const detail = root.querySelector('#capsule-detail');
  const archive = root.querySelector('#capsule-archive');
  const invite = root.querySelector('#capsule-invite');
  const post = root.querySelector('#capsule-post');
  let active = null;
  let generation = 0;

  const request = (action, capsule_id = null, details = null) => api('/rest/v1/rpc/beta_capsules', {
    method: 'POST', body: { action, capsule_id, details },
  });

  const photoRequest = (action, capsule_id, details = null) => api('/rest/v1/rpc/beta_capsule_photos', {
    method: 'POST', body: { action, capsule_id, details },
  });

  function action(control, run) {
    return async event => {
      event.preventDefault();
      control.disabled = true;
      const current = generation;
      try {
        await run(current);
      } catch (error) {
        if (current === generation) status(error.message);
      } finally {
        control.disabled = false;
      }
    };
  }

  function button(parent, label, run) {
    const control = document.createElement('button');
    control.type = 'button';
    control.textContent = label;
    control.onclick = action(control, run);
    parent.append(control);
  }

  function close() {
    active = null;
    detail.hidden = true;
    archive.replaceChildren();
    invite.elements.member_id.replaceChildren();
    post.reset();
  }

  async function open(item) {
    active = item;
    const current = generation;
    detail.hidden = true;
    const [memories, photoIds] = await Promise.all([request('read', item.id), photoRequest('list', item.id)]);
    const photos = new Set(photoIds);
    if (current !== generation || active !== item) return;
    root.querySelector('#capsule-title').textContent = item.title;
    detail.hidden = false;
    invite.hidden = true;
    archive.replaceChildren();
    if (!memories.length) archive.textContent = 'La capsule ne contient encore aucun souvenir.';
    for (const memory of memories) {
      const article = document.createElement('article');
      const name = document.createElement('strong');
      const body = document.createElement('p');
      name.textContent = memory.mine ? 'Moi' : memory.display_name;
      body.textContent = memory.body;
      body.className = 'archive-memory';
      article.append(name, body);
      if (photos.has(memory.id)) {
        button(article, 'Voir la photo', async (generationAtClick) => {
          if (article.querySelector('canvas')) return;
          const photo = await photoRequest('read', item.id, { memory_id: memory.id });
          if (photo && generationAtClick === generation && active === item) {
            article.insertBefore(renderPhoto(photo, memory.body), body);
          }
        });
      }
      if (memory.mine) {
        button(article, 'Retirer ce souvenir', async generationAtClick => {
          await request('remove', item.id, { memory_id: memory.id });
          if (generationAtClick === generation && active === item) await open(item);
        });
      } else {
        button(article, 'Signaler', () => report(memory.author_id));
      }
      archive.append(article);
    }
    if (item.owned) {
      const people = await connections();
      if (current !== generation || active !== item) return;
      const accepted = people.filter(person => person.status === 'accepted');
      const select = invite.elements.member_id;
      select.replaceChildren(...accepted.map(person => new Option(person.display_name, person.person_id)));
      invite.hidden = accepted.length === 0;
    }
  }

  async function refresh() {
    const current = generation;
    const capsules = await request('list');
    if (current !== generation) return;
    list.replaceChildren();
    if (!capsules.length) list.textContent = 'Aucune capsule pour le moment.';
    for (const item of capsules) {
      const article = document.createElement('article');
      const label = document.createElement('strong');
      label.textContent = item.title + ' · ' + item.memory_year;
      article.append(label);
      if (item.joined) {
        button(article, 'Ouvrir la capsule', () => open(item));
      } else {
        button(article, 'Accepter l’invitation', async current => {
          await request('join', item.id);
          if (current === generation) await refresh();
        });
      }
      const leaveLabel = item.owned ? 'Supprimer la capsule' : item.joined ? 'Quitter la capsule' : 'Décliner';
      button(article, leaveLabel, async current => {
        if (item.joined && !window.confirm(item.owned
          ? 'Supprimer la capsule et ses souvenirs pour tous ses membres ?'
          : 'Quitter cette capsule et retirer tes souvenirs ?')) return;
        await request('leave', item.id);
        if (current !== generation) return;
        if (active?.id === item.id) close();
        await refresh();
      });
      list.append(article);
    }
  }

  const submit = form => form.querySelector('[type=submit]');
  creation.onsubmit = action(submit(creation), async current => {
    await request('create', null, Object.fromEntries(new FormData(creation)));
    if (current !== generation) return;
    creation.reset();
    await refresh();
    if (current === generation) status('Capsule créée.');
  });
  invite.onsubmit = action(submit(invite), async current => {
    const item = active;
    if (!item) return;
    await request('invite', item.id, { member_id: invite.elements.member_id.value });
    if (current === generation && active === item) status('Invitation envoyée.');
  });
  post.onsubmit = action(submit(post), async current => {
    const item = active;
    if (!item) return;
    const body = post.elements.body.value;
    const photo = post.elements.photo.files[0];
    if (photo) {
      const prepared = await preparePhoto(photo);
      if (current !== generation || active !== item) return;
      await photoRequest('post', item.id, { body, ...prepared });
    } else {
      await request('post', item.id, { body });
    }
    if (current !== generation || active !== item) return;
    post.reset();
    await open(item);
  });
  root.querySelector('#capsule-close').onclick = close;
  const reload = root.querySelector('#capsule-reload');
  reload.onclick = action(reload, async () => {
    close();
    await refresh();
  });

  return {
    setEntries(rows) {
      const select = creation.elements.entry_id;
      const prior = select.value;
      const options = rows.filter(row => row.visible).map(row =>
        new Option(row.place + ' · ' + row.start_year + '–' + row.end_year, row.id));
      select.replaceChildren(...options);
      if (options.some(option => option.value === prior)) select.value = prior;
      creation.hidden = options.length === 0;
    },
    async show() {
      root.hidden = false;
      try {
        await refresh();
      } catch {
        if (!root.hidden) list.textContent = 'Capsules indisponibles. Réessaie dans un instant.';
      }
    },
    reset() {
      generation++;
      root.hidden = true;
      creation.hidden = true;
      creation.reset();
      creation.elements.entry_id.replaceChildren();
      list.replaceChildren();
      close();
    },
  };
}
