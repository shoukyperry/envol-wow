"""Rendu 3D logiciel de la flèche « cristal » d'Envol (numpy + scipy).

La flèche est un relief (carte de hauteur) : biseau sur les bords et arête centrale, comme un cristal taillé.
Chaque point du relief est projeté dans une vue inclinée, avec tampon de profondeur et éclairage,
puis la flèche est rendue sous N angles.
Usage : python fleche3d.py <sortie> [--angles 64] [--taille 128] [--inclinaison 55] [--couleur Arcane] [--apercu]
Sortie : un atlas TGA compressé RLE (angles en grille), ou des PNG d'aperçu.
"""
import argparse, math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

# contour de la flèche dans le plan (x à droite, y vers l'avant), longueur ~2
CONTOUR = [(0.0, 1.0), (0.64, 0.16), (0.25, 0.22), (0.25, -0.90), (0.0, -1.02),
           (-0.25, -0.90), (-0.25, 0.22), (-0.64, 0.16)]
N = 420                 # résolution du relief
EPAIS = 0.10            # épaisseur du flanc (sous le biseau)

COULEURS = {
    "Arcane": ((0.40, 0.96, 1.00), (0.58, 0.40, 1.00)),
    "Givre":  ((0.90, 0.97, 1.00), (0.58, 0.74, 0.96)),
    "Nature": ((0.55, 1.00, 0.50), (0.10, 0.60, 0.28)),
    "Or":     ((1.00, 0.92, 0.45), (0.92, 0.55, 0.10)),
    "Feu":    ((1.00, 0.75, 0.28), (0.96, 0.22, 0.06)),
    "Sang":   ((1.00, 0.40, 0.40), (0.62, 0.04, 0.10)),
    "Ombre":  ((0.85, 0.52, 1.00), (0.38, 0.10, 0.70)),
}

_relief = None


def relief():
    """Points 3D du dessus (avec normales) et du flanc, calculés une fois."""
    global _relief
    if _relief is not None:
        return _relief
    im = Image.new("L", (N, N), 0)
    ImageDraw.Draw(im).polygon([((x + 1.1) / 2.2 * N, (1.1 - y) / 2.2 * N) for x, y in CONTOUR], fill=255)
    m = np.asarray(im) > 0
    d = ndimage.distance_transform_edt(m) / N * 2.2            # distance au bord, en unités du plan
    ys, xs = np.mgrid[0:N, 0:N]
    X = xs / N * 2.2 - 1.1
    Y = 1.1 - ys / N * 2.2
    # taille du cristal : biseau rapide puis plateau incliné vers l'arête centrale (x = 0)
    biseau = np.minimum(d * 1.6, 0.16)
    arete = 0.10 * np.clip(1 - np.abs(X) / 0.64, 0, 1)
    h = (biseau + arete) * m
    h = ndimage.gaussian_filter(h, 0.6) * m
    gy, gx = np.gradient(h, 2.2 / N)
    nrm = np.dstack([-gx, gy, np.ones_like(h)])                # y image inversé
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    sel = m
    haut = np.column_stack([X[sel], Y[sel], h[sel] + EPAIS])
    nh = nrm[sel]
    k = np.clip((Y[sel] + 1) / 2, 0, 1)                        # dégradé le long de la flèche
    # flanc : points du bord, empilés verticalement
    bord = m & ~ndimage.binary_erosion(m)
    bx, by = X[bord], Y[bord]
    gxb, gyb = ndimage.sobel(m.astype(float), 1)[bord], -ndimage.sobel(m.astype(float), 0)[bord]
    nb = np.column_stack([-gxb, -gyb, np.zeros_like(gxb)])
    nb /= np.maximum(np.linalg.norm(nb, axis=1, keepdims=True), 1e-9)
    etages = np.linspace(0, EPAIS, 10)
    flanc = np.vstack([np.column_stack([bx, by, np.full_like(bx, z)]) for z in etages])
    nf = np.vstack([nb] * len(etages))
    kf = np.tile(np.clip((by + 1) / 2, 0, 1), len(etages))
    _relief = (haut, nh, k, flanc, nf, kf)
    return _relief


def rendre(lacet, inclinaison, taille, couleur, ss=3):
    W = taille * ss
    haut, nh, k, flanc, nf, kf = relief()
    cz, sz = math.cos(lacet), math.sin(lacet)
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    t = math.radians(inclinaison)
    Rx = np.array([[1, 0, 0], [0, math.cos(t), -math.sin(t)], [0, math.sin(t), math.cos(t)]])
    M = Rx @ Rz
    lum = np.array([-0.40, 0.50, 0.77]); lum /= np.linalg.norm(lum)
    hv = lum + np.array([0, 0, 1.0]); hv /= np.linalg.norm(hv)
    c1, c2 = (np.array(c) for c in COULEURS[couleur])

    def ombrer(P, Nn, kk, dessus):
        Q = P @ M.T; Nv = Nn @ M.T
        diff = np.clip(Nv @ lum, 0, 1)
        spec = np.clip(Nv @ hv, 0, 1) ** 40
        frenel = (1 - np.clip(Nv[:, 2], 0, 1)) ** 2
        col = c2[None] * (1 - kk[:, None]) + c1[None] * kk[:, None]
        if dessus:
            rgb = col * (0.30 + 0.80 * diff[:, None]) + spec[:, None] * 1.1 + frenel[:, None] * c1[None] * 0.5
        else:
            rgb = col * (0.18 + 0.40 * diff[:, None]) + spec[:, None] * 0.3
        return Q, np.clip(rgb, 0, 1)

    Q1, r1 = ombrer(haut, nh, k, True)
    Q2, r2 = ombrer(flanc, nf, kf, False)
    Q = np.vstack([Q1, Q2]); R = np.vstack([r1, r2])
    echelle = W * 0.40
    px = np.round(W / 2 + Q[:, 0] * echelle).astype(int)
    py = np.round(W / 2 - Q[:, 1] * echelle).astype(int)
    ok = (px >= 0) & (px < W) & (py >= 0) & (py < W)
    px, py, z, R = px[ok], py[ok], Q[ok, 2], R[ok]
    ordre = np.argsort(z)                     # du plus loin au plus proche : le dernier écrit gagne
    img = np.zeros((W, W, 4))
    img[py[ordre], px[ordre], :3] = R[ordre]
    img[py[ordre], px[ordre], 3] = 1
    # bouche les trous éventuels entre points
    a = img[:, :, 3] > 0
    plein = ndimage.binary_closing(a, iterations=2)
    for c in range(3):
        canal = img[:, :, c]
        flou = ndimage.grey_dilation(canal, size=3)
        canal[plein & ~a] = flou[plein & ~a]
    img[:, :, 3] = plein
    im = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    # liseré et lueur
    al = im.split()[3]
    bord = al.filter(ImageFilter.MaxFilter(ss * 2 + 1))
    lueur = bord.filter(ImageFilter.GaussianBlur(ss * 3))
    teinte = tuple(int(255 * min(1, v)) for v in c1)
    halo = Image.new("RGBA", im.size, teinte + (0,)); halo.putalpha(lueur.point(lambda v: int(v * 0.5)))
    lis = Image.new("RGBA", im.size, tuple(int(255 * (0.65 + 0.35 * v)) for v in c1) + (0,))
    lis.putalpha(Image.fromarray(np.clip(np.asarray(bord, np.int32) - np.asarray(al, np.int32), 0, 255).astype(np.uint8)))
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(halo); out.alpha_composite(lis); out.alpha_composite(im)
    return out.resize((taille, taille), Image.LANCZOS)


def tga_rle(im, chemin):
    """TGA 32 bits compressé RLE (type 10), origine en haut à gauche ; paquets sans changer de ligne."""
    w, h = im.size
    tout = np.ascontiguousarray(np.asarray(im.convert("RGBA"))[:, :, [2, 1, 0, 3]])
    out = bytearray()
    for y in range(h):
        px = tout[y]
        cle = px.view(np.uint32).ravel()
        i, n = 0, w
        while i < n:
            j = i + 1
            while j < n and j - i < 128 and cle[j] == cle[i]:
                j += 1
            if j - i > 1:
                out.append(0x80 | (j - i - 1)); out += px[i].tobytes(); i = j
                continue
            j = i + 1
            while j < n and j - i < 128 and not (j + 1 < n and cle[j] == cle[j + 1]):
                j += 1
            out.append(j - i - 1); out += px[i:j].tobytes(); i = j
    entete = bytes([0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + w.to_bytes(2, "little") + h.to_bytes(2, "little") + bytes([32, 0x28])
    open(chemin, "wb").write(entete + bytes(out))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("sortie")
    ap.add_argument("--angles", type=int, default=64)
    ap.add_argument("--taille", type=int, default=128)
    ap.add_argument("--inclinaison", type=float, default=55)
    ap.add_argument("--couleur", default="Arcane")
    ap.add_argument("--apercu", action="store_true")
    a = ap.parse_args()
    imgs = [rendre(2 * math.pi * i / a.angles, a.inclinaison, a.taille, a.couleur) for i in range(a.angles)]
    if a.apercu:
        os.makedirs(a.sortie, exist_ok=True)
        for i, im in enumerate(imgs):
            im.save(os.path.join(a.sortie, f"{i:02d}.png"))
    else:
        cote = int(math.ceil(math.sqrt(a.angles)))
        atlas = Image.new("RGBA", (cote * a.taille, cote * a.taille), (0, 0, 0, 0))
        for i, im in enumerate(imgs):
            atlas.paste(im, ((i % cote) * a.taille, (i // cote) * a.taille))
        tga_rle(atlas, a.sortie)
        print(a.sortie, os.path.getsize(a.sortie) // 1024, "Ko")
