import coremltools   
import h5py

output_labels = ['left','right','start','ballkicker'] 
coreml_model = coremltools.converters.keras.convert('model.h5',input_names='image',image_input_names = 'image',class_labels = output_labels)   
coreml_model.author = 'Rocco Bowling'   
coreml_model.short_description = 'This is how we play pinball machines'   
coreml_model.input_description['image'] = 'Image of the play area of the pinball machine'   
coreml_model.save('model.mlmodel') 