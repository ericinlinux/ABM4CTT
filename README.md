# Crime Data Analysis in Lavras (Brazil)
#### Dr. Eric Fernandes de Mello Araújo
###### Universidade Federal de Lavras (Brazil)
###### Vrije Universiteit Amsterdam (The Netherlands)
---




## Convert OSM to Shapefile
https://geoconverter.hsr.ch/vector
https://wiki.openstreetmap.org/wiki/Converting_map_data_between_formats

##### Final notes to myself

To remove the 6 first lines of the csv file

```
sed -e '1,6d' < phase_04a-table.csv > phase_04a.csv
```