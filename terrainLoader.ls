P = require 'bluebird'
{PLoader} = require './ThreePromise.ls'
THREE = require 'three'
Cannon = require 'cannon'

class NicerImageData
	({@width, @height}, {@data}) ->

	i: (x, y) ->
		i = y*(@width*4) + x*4

	pixel: (x, y) ->
		i = @i x, y
		return @data[i til i + 4]

export getImageData = (url) ->
	PLoader(THREE.ImageLoader) url
	.then ([img]) ->
		canvas = document.createElement 'canvas'
			..width = img.width
			..height = img.height
		context = canvas.getContext '2d'
		context.drawImage img, 0, 0
		w = img.width
		h = img.height
		data = context.getImageData(0, 0, w, h)
		return new NicerImageData({width: w, height: h}, data)



export getHeightmap = (image, heightScale=1) ->
	m = for y in [0 til image.height]
		for x in [0 til image.width]
			p = (image.pixel x, y)[0 til -1]
			v = p.reduce (a, b) -> a + b
			v /= 255*4
			v *= heightScale


export getTerrain = ({hUrl, hscale=1, xzscale=1, texUrl, texSize, renderer}) ->
	image = getImageData hUrl
	texture = (PLoader THREE.TextureLoader) texUrl
	P.join image, texture, (image, [texture]) ->
		heights = getHeightmap(image, hscale)
		nh = heights.length
		nw = heights[0].length
		w = (nw) * xzscale - xzscale
		h = (nh) * xzscale - xzscale
		hfShape = new Cannon.Heightfield heights, {elementSize: xzscale}

		pos = new Cannon.Vec3 h/2.0, 0, -w
		pos = new Cannon.Vec3 -w/2.0, 0, -h/2.0
		rot = (new Cannon.Quaternion)
		rot.setFromEuler -Math.PI/2.0, 0, -Math.PI/2.0, 'XYZ'

		hfBody = new Cannon.Body mass: 0
			..addShape hfShape, pos, rot
			#..quaternion.

		geo = new THREE.PlaneGeometry do
			w
			h
			heights[0].length-1
			heights.length-1

		for row, y in heights
			for val, x in row
				i = y*row.length + x
				geo.vertices[i].z = val

		geo.computeFaceNormals()
		geo.computeVertexNormals()

		texture.wrapS = texture.wrapT = THREE.RepeatWrapping
		wRep = w/texSize
		hRep = h/texSize
		texture.repeat.set wRep, hRep
		texture.anisotropy = renderer.getMaxAnisotropy()

		material = new THREE.MeshLambertMaterial do
			map: texture
			shading: THREE.SmoothShading
		mesh = new THREE.Mesh geo, material
		mesh.rotation.x = -Math.PI/2.0

		phys: hfBody
		mesh: mesh

/*
//return array with height data from img
function getHeightData(img,scale) {
  
 if (scale == undefined) scale=1;
  
    var canvas = document.createElement( 'canvas' );
    canvas.width = img.width;
    canvas.height = img.height;
    var context = canvas.getContext( '2d' );
 
    var size = img.width * img.height;
    var data = new Float32Array( size );
 
    context.drawImage(img,0,0);
 
    for ( var i = 0; i < size; i ++ ) {
        data[i] = 0
    }
 
    var imgd = context.getImageData(0, 0, img.width, img.height);
    var pix = imgd.data;
 
    var j=0;
    for (var i = 0; i<pix.length; i +=4) {
        var all = pix[i]+pix[i+1]+pix[i+2];
        data[j++] = all/(12*scale);
    }
     
    return data;
}``
*/
