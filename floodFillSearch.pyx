# cython: profile=True
from numpy import *
cimport numpy as np
import cProfile
cimport cython

cdef inline int ravel_shift(   tuple indices, \
                                int arrayRank, \
                                np.ndarray[np.int_t,ndim=1] arrayShape, \
                                int dimension,  \
                                int amount,     \
                                int dimensionWraps):
    """Return the raveled index of a shifted version of indices, where a
    specific dimension has been shifted by a certain amount.  If wrapping is
    not flagged and the shift is out of bounds, returns -1"""


    cdef int runningProduct
    cdef int n
    cdef int i
    cdef int np
    cdef int thisIndex

    runningProduct = 1
    i = 0

    #Loop over dimensions, starting at the rightmost dimension
    for n in xrange(arrayRank,0,-1):
        #Calculate the running product of dimension sizes
        if( n != arrayRank):
            runningProduct *= arrayShape[n]

        #Set the current index
        thisIndex = indices[n-1]

        np = n-1
        if(np == dimension):
            #If this is the shifting dimension,
            #increment it
            thisIndex += amount

            #Check if we need to deal with a
            #wrap around dimension
            if(dimensionWraps):
                if(thisIndex < 0):
                    thisIndex += arrayShape[np]
                if(thisIndex >= arrayShape[np]):
                    thisIndex -= arrayShape[np]

            #Check if the current index is out of bounds;
            #return -1 if so
            if(thisIndex < 0 or thisIndex >= arrayShape[np]):
                i = -1
                break

        #increment the counter
        i += runningProduct*thisIndex

    #Check whether the index is within the memory bounds of the array
    #return the -1 flag if not
    runningProduct *= arrayShape[0]
    if(i >= runningProduct or i < 0):
        i = -1

    return i

@cython.boundscheck(False)
cdef tuple findNeighbors(   int raveledStartIndex, \
                            np.float_t searchThreshold, \
                            np.ndarray[np.int_t,ndim=1] arrayShape, \
                            int arrayRank, \
                            list dimensionWraps, \
                            np.ndarray[np.float_t,ndim=1] inputArray, \
                            np.ndarray[np.int_t,ndim=1] isNotSearched, \
                   ):
    """Does a flood fill algorithim on inputArray in the vicinity of
    raveledStartIndex to find contiguous areas where raveledStartIndex >= searchThreshold 
    
        input:
        ------
            raveledStartIndex   :   (integer) the index of inputArray.ravel() at which to start

            searchThreshold :   The threshold for defining fill regions
                                (inputArray > searchThreshold)

        output:
        -------
            A list of N-d array indices.
    
    """

    
    cdef list itemsToSearch #Running item search list
    cdef list contiguousIndices #A list of indices
    cdef int r #Current array dimension
    cdef int testIndexLeft # A test index
    cdef int testIndexRight # A test index
    cdef tuple contiguousArray #A tuple of contiguous indices
    cdef np.ndarray contiguousIndexArray #An array of contiguous indices
    cdef int testInd #The raveled index of the test point

    cdef tuple itemTuple #The tuple index of the current search item

    cdef int shiftAmount

    #Initialize the contiguous index list
    contiguousIndices = []

    #Initialize the search list
    #itemsToSearch = [list(unravel_index(raveledStartIndex,arrayShape))]
    itemsToSearch = [raveledStartIndex]

    while itemsToSearch != []:

        #Get the index of the current item
        itemTuple = unravel_index(itemsToSearch[0],arrayShape)

        for r in xrange(arrayRank):
            #Shift the current coordinate to the right by 1 in the r dimension
            shiftAmount = 1
            testIndexRight = ravel_shift( \
                                        itemTuple, \
                                        arrayRank, \
                                        arrayShape, \
                                        r, \
                                        shiftAmount,
                                        dimensionWraps[r])

            #Check that this coordinate is still within bounds
            if(testIndexRight >= 0):
                #Check if this index satisfies the search condition
                if(inputArray[testIndexRight] > searchThreshold and \
                        isNotSearched[testIndexRight] == 1):
                    #Append it to the search list if so
                    itemsToSearch.append(testIndexRight)
                    #Flags that this cell has been searched
                    isNotSearched[testIndexRight] = 0


            #Shift the current coordinate to the right by 1 in the r dimension
            shiftAmount = -1
            testIndexLeft = ravel_shift( \
                                        itemTuple, \
                                        arrayRank, \
                                        arrayShape, \
                                        r, \
                                        shiftAmount,
                                        dimensionWraps[r])

            #Check that this coordinate is still within bounds
            if(testIndexLeft > 0):
                #Check if this index satisfies the search condition
                if(inputArray[testIndexLeft] > searchThreshold and \
                        isNotSearched[testIndexLeft] == 1 ):
                    #Append it to the search list if so
                    itemsToSearch.append(testIndexLeft)
                    #Flags that this cell has been searched
                    isNotSearched[testIndexLeft] = 0

 

        #Flag that this index has been searched
        #isNotSearched[tuple(itemsToSearch[0])] = 0
        #Now that the neighbors of the first item in the list have been tested,
        #remove it from the list and put it in the list of contiguous values
        contiguousIndices.append(itemsToSearch.pop(0))

    #Return the list of contiguous indices (converted to index tuples)
    return unravel_index(contiguousIndices,arrayShape)

cpdef list floodFillSearch( \
                np.ndarray inputArray, \
                np.float_t searchThreshold = 0.0, \
                wrapDimensions = None):
    """Given an N-dimensional array, find contiguous areas of the array
    satisfiying a given condition and return a list of contiguous indices
    for each contiguous area.
        
        input:
        ------

            inputArray      :   (array-like) an array from which to search
                                contiguous areas

            searchThreshold :   The threshold for defining fill regions
                                (inputArray > searchThreshold)

            wrapDimensions :    A list of dimensions in which searching
                                should have a wraparound condition

        output:
        -------

            An unordered list, where each item corresponds to a unique
            contiguous area for which inputArray > searchThreshold, and
            where the contents of each item are a list of array indicies
            that access the elements of the array for a given contiguous
            area.

    """
    cdef np.ndarray[np.int_t,ndim=1] arrayShape
    cdef int arrayRank
    cdef int numArrayElements
    cdef list dimensionWraps
    cdef list contiguousAreas

    cdef tuple contiguousArray 

    #Determine the rank of inputArray
    try:
        arrayShape = array(shape(inputArray))
        arrayRank = len(arrayShape)
        numArrayElements = prod(arrayShape)
    except BaseException as e:
        raise ValueError,"inputArray does not appear to be array like.  Error was: {}".format(e)

    #Set the dimension wrapping array
    dimensionWraps = arrayRank*[False]
    if wrapDimensions is not None:
        try:
            dimensionWraps[list(wrapDimensions)] = True
        except BaseException as e:
            raise ValueError,"wrapDimensions must be a list of valid dimensions for inputArray. Original error was: {}".format(e)

    #Set an array of the same size indicating which elements have been set
    cdef np.ndarray isNotSearched
    isNotSearched = ones(arrayShape,dtype = 'int')

    #Set the raveled input array
    cdef np.ndarray[np.float_t,ndim=1] raveledInputArray = inputArray.ravel()
    #And ravel the search inidcator array
    cdef np.ndarray[np.int_t,ndim=1] raveledIsNotSearched = isNotSearched.ravel()
    
    #Set the search list to null
    contiguousAreas = []

    cdef int i
    #Loop over the array
    for i in xrange(numArrayElements):
        #print "{}/{}".format(i,numArrayElements)
        #Check if the current element meets the search condition
        if raveledInputArray[i] >= searchThreshold and raveledIsNotSearched[i]:
            #Flag that this cell has been searched
            raveledIsNotSearched[i] = 0

            #If it does, use a flood fill search to find the contiguous area surrouinding
            #the element for which the search condition is satisified. At very least, the index
            #of this element is appended to contiguousAreas
            contiguousAreas.append(\
                                    findNeighbors(  i,  \
                                                    searchThreshold,    \
                                                    arrayShape,         \
                                                    arrayRank,          \
                                                    dimensionWraps,     \
                                                    raveledInputArray,         \
                                                    raveledIsNotSearched      ))

        else:
            #Flag that this cell has been searched
            raveledIsNotSearched[i] = 0
                                    


    #Set the list of contiguous area indices
    return contiguousAreas


def sortByDistanceFromCenter(inds,varShape):
    """Takes sets of indicies [e.g., from floodFillSearchC.floodFillSearch()] and sorts them by distance from the center of the array from which the indices were taken.
    
        input:
        ------
        
            inds     :  a list of tuples of numpy ndarrays (of type integer and
                        rank 1), where each tuple item contains a vector of
                        indices for each index of an array.  Each list item
                        should conform to the output of the numpy where()
                        function.  It is assumed that each set of indices
                        represents a contiguous portion of an array.
                       
            varShape : the shape of the variable from which inds originate
            
        returns:
        --------

             A sorted version of inds, where the items are sorted by the
             distance of the contiguous area relative to the center of the
             array whose shape is varShape.  The first item is the closest to
             the center of the array.
             
    """
    #Get the center index
    center = around(array(varShape)/2)
    
    #Transform the indices to be center-relative
    centeredInds = [ tuple([ aind - cind] for aind,cind in zip(indTuples,center)) for indTuples in inds ]
    
    #Calculate center-of-mass ffor each contiguous array
    centersOfMass = [ array([average(aind) for aind in indTuples]) for indTuples in centeredInds]
    
    #Calculate the distance from the origin of each center of mass
    distances = [ sqrt(sum(indices**2)) for indices in centersOfMass]
    
    #Determine the sorting indices that will sort inds by distance from the center
    isort = list(argsort(distances))
    
    #Return the sorted index array
    return [inds[i] for i in isort]
